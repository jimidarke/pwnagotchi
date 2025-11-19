FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies without progress bar to avoid threading issues
RUN pip install --no-cache-dir --progress-bar off -r requirements.txt

# Copy application code
COPY app.py .

# Create directories for data and uploads
RUN mkdir -p /app/data /app/uploads/handshakes /app/uploads/logs

# Expose port
EXPOSE 5000

# Run with gunicorn for production
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "120", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
