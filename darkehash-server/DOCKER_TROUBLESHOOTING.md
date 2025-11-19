# Docker Build Troubleshooting

## Issue: Docker build failing

### Solution 1: Clean Docker cache

```bash
# Remove old containers and images
docker-compose down
docker system prune -af
docker volume prune -f

# Rebuild
docker-compose up -d --build
```

### Solution 2: Check disk space

```bash
# Check available disk space
df -h

# Check Docker disk usage
docker system df

# Clean up Docker (removes all unused data)
docker system prune -a --volumes
```

### Solution 3: Pull base image manually

```bash
# Pull the base image first
docker pull python:3.11-slim

# Then build
docker-compose build --no-cache
docker-compose up -d
```

### Solution 4: Build without cache

```bash
docker-compose build --no-cache --pull
docker-compose up -d
```

### Solution 5: Increase Docker resources

If using Docker Desktop:
- Open Docker Desktop settings
- Go to Resources
- Increase disk space allocation
- Increase memory if needed
- Click "Apply & Restart"

### Solution 6: Alternative - Run without Docker

If Docker continues to fail, you can run the server directly:

```bash
# Install Python 3.11+ if not already installed
python3 --version

# Install dependencies
pip3 install -r requirements.txt

# Set environment variables
export AUTH_USERNAME=darkepwn
export AUTH_PASSWORD=dh2akf5ksdai44ad0y
export PORT=8800
export DB_PATH=./data/darkehash.db
export UPLOAD_DIR=./uploads

# Create directories
mkdir -p data uploads/handshakes uploads/logs

# Run the server
python3 app.py

# Or with gunicorn for production
gunicorn --bind 0.0.0.0:8800 --workers 4 --timeout 120 app:app
```

### Solution 7: Use pre-built image

Create a simpler Dockerfile:

```dockerfile
FROM python:3.11-alpine

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
RUN mkdir -p /app/data /app/uploads/handshakes /app/uploads/logs

EXPOSE 5000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "120", "app:app"]
```

### Check build logs

```bash
# Build with verbose output
docker-compose build --progress=plain

# Check Docker daemon logs
journalctl -u docker.service -n 100
```

### Verify requirements.txt

Make sure `requirements.txt` contains only:
```
Flask==3.0.0
Werkzeug==3.0.1
gunicorn==21.2.0
```

### Test Python dependencies locally

```bash
# Test if packages install locally
pip3 install Flask==3.0.0 Werkzeug==3.0.1 gunicorn==21.2.0

# If that works, Docker should work too
```

## Common Errors and Solutions

### Error: "no space left on device"
```bash
# Clean Docker
docker system prune -a --volumes

# Clean system
sudo apt-get clean
sudo apt-get autoclean
```

### Error: "Cannot connect to Docker daemon"
```bash
# Start Docker service
sudo systemctl start docker

# Check status
sudo systemctl status docker
```

### Error: "permission denied"
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Log out and back in, or:
newgrp docker
```

### Error: Network issues during build
```bash
# Use different DNS
echo '{"dns": ["8.8.8.8", "8.8.4.4"]}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker
```

## Minimal Docker Setup

If all else fails, here's the absolute minimal setup:

**Dockerfile.minimal:**
```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt app.py ./
RUN pip install --no-cache-dir -r requirements.txt
RUN mkdir -p /app/data /app/uploads
CMD ["python", "app.py"]
```

**docker-compose.minimal.yml:**
```yaml
version: '3.8'
services:
  darkehash:
    build:
      context: .
      dockerfile: Dockerfile.minimal
    ports:
      - "8800:5000"
    environment:
      - AUTH_USERNAME=darkepwn
      - AUTH_PASSWORD=dh2akf5ksdai44ad0y
      - PORT=5000
    volumes:
      - ./data:/app/data
      - ./uploads:/app/uploads
```

Build with:
```bash
docker-compose -f docker-compose.minimal.yml up -d --build
```
