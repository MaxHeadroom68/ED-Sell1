
# A stub, to demonstrate that Sell1.ahk calls it properly
import sys
import os
import datetime

# Get the status from environment variable
status = os.environ.get('SELL1_STATUS', 'UNKNOWN')
salesize = os.environ.get('SELL1_SALESIZE', 'UNKNOWN')
sold = os.environ.get('SELL1_SOLD', 'UNKNOWN')
retries = os.environ.get('SELL1_RETRIES', 'UNKNOWN')

# Create timestamp
timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')

# script name
scriptname = os.path.basename(sys.argv[0])

# Log entry
log_entry = f"{timestamp} {scriptname} Sell1 status={status} salesize={salesize} sold={sold} retries={retries}\n"

# Create log directory if it doesn't exist
log_dir = os.path.join(os.environ['LOCALAPPDATA'], 'Sell1')
os.makedirs(log_dir, exist_ok=True)

# Full path to log file
log_file = os.path.join(log_dir, 'notify.log')

# Append to log file
with open(log_file, 'a') as f:
    f.write(log_entry)

print(f"log_file={log_file}")
print(f"Logged status: {status}")

