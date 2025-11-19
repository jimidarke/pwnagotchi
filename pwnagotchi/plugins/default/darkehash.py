import os
import logging
import sqlite3
import requests
from datetime import datetime, timedelta
from threading import Lock
from pwnagotchi.utils import remove_whitelisted
from pwnagotchi import plugins
from pwnagotchi.ui.components import LabeledValue
from pwnagotchi.ui.view import BLACK
import pwnagotchi.ui.fonts as fonts


class DarkeHash(plugins.Plugin):
    __author__ = 'darkehash@custom.local'
    __version__ = '1.0.0'
    __license__ = 'GPL3'
    __description__ = 'Uploads handshakes and logs to a custom server endpoint'

    class Status:
        PENDING = 0
        UPLOADED = 1
        FAILED = 2

    def __init__(self):
        self.ready = False
        self.lock = Lock()
        self.options = dict()
        self.handshake_dir = '/home/pi/handshakes'
        self.log_path = '/var/log/pwnagotchi.log'
        self.bootup_logs_sent = False
        self._init_db()

    def _init_db(self):
        """Initialize SQLite database for tracking uploads"""
        db_conn = sqlite3.connect('/home/pi/.darkehash_db')
        db_conn.execute('pragma journal_mode=wal')
        with db_conn:
            db_conn.execute('''
                CREATE TABLE IF NOT EXISTS handshakes (
                    path TEXT PRIMARY KEY,
                    status INTEGER,
                    uploaded_at TIMESTAMP,
                    retry_count INTEGER DEFAULT 0
                )
            ''')
            db_conn.execute('''
                CREATE INDEX IF NOT EXISTS idx_handshakes_status
                ON handshakes (status)
            ''')
            db_conn.execute('''
                CREATE TABLE IF NOT EXISTS status_uploads (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    uploaded_at TIMESTAMP,
                    upload_type TEXT DEFAULT 'regular'
                )
            ''')
        db_conn.close()

    def _check_bootup_status(self):
        """Check if bootup logs have been sent since last reboot"""
        try:
            # Get system boot time
            with open('/proc/uptime', 'r') as f:
                uptime_seconds = float(f.readline().split()[0])

            boot_time = datetime.now() - timedelta(seconds=uptime_seconds)

            # Check if we've sent bootup logs since boot
            db_conn = sqlite3.connect('/home/pi/.darkehash_db')
            cursor = db_conn.cursor()
            cursor.execute('''
                SELECT uploaded_at FROM status_uploads
                WHERE upload_type = 'bootup'
                ORDER BY uploaded_at DESC LIMIT 1
            ''')
            result = cursor.fetchone()
            cursor.close()
            db_conn.close()

            if result:
                last_bootup = datetime.strptime(result[0], '%Y-%m-%d %H:%M:%S.%f')
                if last_bootup > boot_time:
                    self.bootup_logs_sent = True
                    logging.debug("DARKEHASH: Bootup logs already sent this session")
                    return

            logging.debug("DARKEHASH: Bootup logs need to be sent")
            self.bootup_logs_sent = False

        except Exception as e:
            logging.error(f"DARKEHASH: Error checking bootup status: {e}")
            self.bootup_logs_sent = False

    def on_loaded(self):
        """Gets called when the plugin gets loaded"""
        # Validate required configuration
        if 'server_url' not in self.options or not self.options['server_url']:
            logging.error("DARKEHASH: server_url is required in configuration")
            return

        if 'username' not in self.options or not self.options['username']:
            logging.error("DARKEHASH: username is required in configuration")
            return

        if 'password' not in self.options or not self.options['password']:
            logging.error("DARKEHASH: password is required in configuration")
            return

        # Set defaults
        self.upload_logs = self.options.get('upload_logs', True)
        self.log_lines = int(self.options.get('log_lines', 200))
        self.max_retries = int(self.options.get('max_retries', 3))

        # Check if bootup logs have been sent in this session
        self._check_bootup_status()

        self.ready = True
        logging.info("DARKEHASH: Plugin loaded and ready")

    def on_config_changed(self, config):
        """Called after config is loaded"""
        self.handshake_dir = config['bettercap']['handshakes']
        self.log_path = config['main']['log'].get('path', '/var/log/pwnagotchi.log')
        self.whitelist = config['main']['whitelist']

    def on_handshake(self, agent, filename, access_point, client_station):
        """Called when a new handshake is captured"""
        config = agent.config()

        # Skip whitelisted networks
        if not remove_whitelisted([filename], config['main']['whitelist']):
            logging.debug(f"DARKEHASH: Skipping whitelisted handshake {filename}")
            return

        # Add to database for upload
        db_conn = sqlite3.connect('/home/pi/.darkehash_db')
        with db_conn:
            db_conn.execute('''
                INSERT INTO handshakes (path, status, retry_count)
                VALUES (?, ?, 0)
                ON CONFLICT(path) DO UPDATE SET
                    status = excluded.status,
                    retry_count = 0
                WHERE handshakes.status = ?
            ''', (filename, self.Status.PENDING, self.Status.FAILED))
        db_conn.close()
        logging.debug(f"DARKEHASH: Queued handshake {filename} for upload")

    def on_internet_available(self, agent):
        """Called when there's internet connectivity"""
        if not self.ready or self.lock.locked():
            return

        with self.lock:
            display = agent.view()

            # Send bootup logs on first internet connection
            if not self.bootup_logs_sent and self.upload_logs:
                try:
                    logging.info("DARKEHASH: Sending bootup logs...")
                    self._upload_status(agent, upload_type='bootup')
                    self.bootup_logs_sent = True
                except Exception:
                    logging.exception("DARKEHASH: Exception during bootup log upload")

            # Upload pending handshakes
            try:
                self._upload_handshakes(display)
            except Exception:
                logging.exception("DARKEHASH: Exception during handshake upload")

            # Upload regular status and logs
            try:
                if self.upload_logs:
                    self._upload_status(agent, upload_type='regular')
            except Exception:
                logging.exception("DARKEHASH: Exception during status upload")

    def _upload_handshakes(self, display):
        """Upload all pending handshakes"""
        db_conn = sqlite3.connect('/home/pi/.darkehash_db')
        cursor = db_conn.cursor()

        # Get pending handshakes that haven't exceeded retry limit
        cursor.execute('''
            SELECT path, retry_count FROM handshakes
            WHERE status = ? AND retry_count < ?
        ''', (self.Status.PENDING, self.max_retries))

        handshakes_to_upload = cursor.fetchall()

        if not handshakes_to_upload:
            cursor.close()
            db_conn.close()
            return

        logging.info(f"DARKEHASH: Found {len(handshakes_to_upload)} handshake(s) to upload")

        for idx, (handshake_path, retry_count) in enumerate(handshakes_to_upload):
            display.on_uploading(f"DarkeHash ({idx + 1}/{len(handshakes_to_upload)})")

            if not os.path.exists(handshake_path):
                logging.warning(f"DARKEHASH: File not found {handshake_path}, removing from queue")
                cursor.execute('DELETE FROM handshakes WHERE path = ?', (handshake_path,))
                db_conn.commit()
                continue

            try:
                logging.info(f"DARKEHASH: Uploading {handshake_path}...")
                self._upload_handshake_file(handshake_path)

                # Mark as uploaded
                cursor.execute('''
                    UPDATE handshakes
                    SET status = ?, uploaded_at = ?
                    WHERE path = ?
                ''', (self.Status.UPLOADED, datetime.now(), handshake_path))
                db_conn.commit()

                logging.info(f"DARKEHASH: Successfully uploaded {handshake_path}")

            except requests.exceptions.RequestException as e:
                logging.error(f"DARKEHASH: Network error uploading {handshake_path}: {e}")
                cursor.execute('''
                    UPDATE handshakes
                    SET retry_count = retry_count + 1,
                        status = CASE WHEN retry_count + 1 >= ? THEN ? ELSE ? END
                    WHERE path = ?
                ''', (self.max_retries, self.Status.FAILED, self.Status.PENDING, handshake_path))
                db_conn.commit()

            except Exception as e:
                logging.exception(f"DARKEHASH: Unexpected error uploading {handshake_path}")
                cursor.execute('''
                    UPDATE handshakes
                    SET status = ?, retry_count = retry_count + 1
                    WHERE path = ?
                ''', (self.Status.FAILED, handshake_path))
                db_conn.commit()

        display.on_normal()
        cursor.close()
        db_conn.close()

    def _upload_handshake_file(self, path, timeout=30):
        """Upload a single handshake file to the server"""
        filename = os.path.basename(path)

        with open(path, 'rb') as f:
            files = {'handshake': (filename, f, 'application/vnd.tcpdump.pcap')}

            # Extract metadata from filename if possible
            # Format: SSID_BSSID.pcap
            metadata = {}
            try:
                base_name = filename.replace('.pcap', '')
                if '_' in base_name:
                    parts = base_name.rsplit('_', 1)
                    if len(parts) == 2:
                        metadata['ssid'] = parts[0]
                        metadata['bssid'] = parts[1]
            except Exception:
                pass

            response = requests.post(
                f"{self.options['server_url'].rstrip('/')}/api/upload/handshake",
                files=files,
                data=metadata,
                auth=(self.options['username'], self.options['password']),
                timeout=timeout
            )
            response.raise_for_status()

            return response.json()

    def _upload_status(self, agent, upload_type='regular'):
        """Upload status information and recent logs"""
        config = agent.config()

        # Read recent log entries
        log_data = ""
        try:
            if os.path.exists(self.log_path):
                with open(self.log_path, 'r') as f:
                    lines = f.readlines()
                    log_data = ''.join(lines[-self.log_lines:])
        except Exception as e:
            logging.error(f"DARKEHASH: Error reading log file: {e}")
            log_data = f"Error reading logs: {e}"

        # Gather status information
        status_info = {
            'device_name': config['main']['name'],
            'timestamp': datetime.now().isoformat(),
            'upload_type': upload_type,
            'log_data': log_data,
            'system_info': {
                'uptime': self._get_uptime(),
                'version': agent.version,
            }
        }

        # Get handshake statistics
        db_conn = sqlite3.connect('/home/pi/.darkehash_db')
        cursor = db_conn.cursor()
        cursor.execute('SELECT COUNT(*) FROM handshakes WHERE status = ?', (self.Status.UPLOADED,))
        uploaded_count = cursor.fetchone()[0]
        cursor.execute('SELECT COUNT(*) FROM handshakes WHERE status = ?', (self.Status.PENDING,))
        pending_count = cursor.fetchone()[0]
        cursor.close()
        db_conn.close()

        status_info['system_info']['handshakes_uploaded'] = uploaded_count
        status_info['system_info']['handshakes_pending'] = pending_count

        # Upload status
        try:
            response = requests.post(
                f"{self.options['server_url'].rstrip('/')}/api/upload/status",
                json=status_info,
                auth=(self.options['username'], self.options['password']),
                timeout=30
            )
            response.raise_for_status()

            # Record status upload
            db_conn = sqlite3.connect('/home/pi/.darkehash_db')
            with db_conn:
                db_conn.execute(
                    'INSERT INTO status_uploads (uploaded_at, upload_type) VALUES (?, ?)',
                    (datetime.now(), upload_type)
                )
            db_conn.close()

            if upload_type == 'bootup':
                logging.info("DARKEHASH: Bootup logs uploaded successfully")
            else:
                logging.info("DARKEHASH: Status and logs uploaded successfully")

        except Exception as e:
            logging.error(f"DARKEHASH: Error uploading status: {e}")

    def _get_uptime(self):
        """Get system uptime in seconds"""
        try:
            with open('/proc/uptime', 'r') as f:
                uptime_seconds = float(f.readline().split()[0])
                return uptime_seconds
        except Exception:
            return 0

    def on_ui_setup(self, ui):
        """Setup UI elements if configured"""
        if self.options.get('show_status', False):
            ui.add_element('darkehash', LabeledValue(
                color=BLACK,
                label='DH:',
                value='',
                position=(0, 95),
                label_font=fonts.Bold,
                text_font=fonts.Small
            ))

    def on_ui_update(self, ui):
        """Update UI with upload statistics"""
        if self.options.get('show_status', False):
            try:
                db_conn = sqlite3.connect('/home/pi/.darkehash_db')
                cursor = db_conn.cursor()
                cursor.execute('SELECT COUNT(*) FROM handshakes WHERE status = ?', (self.Status.UPLOADED,))
                uploaded = cursor.fetchone()[0]
                cursor.execute('SELECT COUNT(*) FROM handshakes WHERE status = ?', (self.Status.PENDING,))
                pending = cursor.fetchone()[0]
                cursor.close()
                db_conn.close()

                ui.set('darkehash', f"{uploaded}↑ {pending}⏳")
            except Exception:
                ui.set('darkehash', 'ERR')

    def on_unload(self, ui):
        """Cleanup when plugin is unloaded"""
        if self.options.get('show_status', False):
            with ui._lock:
                try:
                    ui.remove_element('darkehash')
                except Exception:
                    pass
