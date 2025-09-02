# log to notify.log, and Discord via webhook
# for usage, see the README on github
import sys
import os
import datetime
import configparser
from discord_webhook import DiscordWebhook

# Get the status from environment variable
status      = os.environ.get('SELL1_STATUS',    'UNKNOWN')
salesize    = os.environ.get('SELL1_SALESIZE',  'UNKNOWN')
sold        = os.environ.get('SELL1_SOLD',      'UNKNOWN')
retries     = os.environ.get('SELL1_RETRIES',   'UNKNOWN')
appname     = 'Sell1'

# Create timestamp
timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')

# script name
scriptname = os.path.basename(sys.argv[0])

# Log entry
log_entry = f"{timestamp} {scriptname} {appname} status={status} salesize={salesize} sold={sold} retries={retries}\n"

# Create log directory if it doesn't exist
log_dir = os.path.join(os.environ['LOCALAPPDATA'], appname)
os.makedirs(log_dir, exist_ok=True)

# Full path to log file
log_file = os.path.join(log_dir, 'notify.log')

# Append to log file
with open(log_file, 'a') as f:
    f.write(log_entry)

print(f"log_file={log_file}")
print(f"Logged status: {status}")

############################################
# send the same message to Discord

def load_config():
    # Get config path
    appdata = os.environ.get('APPDATA')
    if not appdata:
        print("Error: Could not find APPDATA directory")
        sys.exit(1)
    
    config_file = os.path.join(appdata, appname, 'config.ini')
    
    # Check if config file exists
    if not os.path.exists(config_file):
        print(f"Error: Config file not found at:")
        print(f"  {config_file}")
        sys.exit(1)
    
    # Try different encodings in order of likelihood
    encodings = ['utf-16', 'utf-8', 'cp1252', 'ascii']                # Hey, did you know that AutoHotKey's IniWrite() creates new files in UTF-16 by default?  NEITHER DID I
    
    config = configparser.ConfigParser()
    
    e1 = ""
    for encoding in encodings:
        try:
            config.read(config_file, encoding=encoding)
            # Test if we actually got content
            if config.sections():
                print(f"Successfully read config using {encoding} encoding")
                break
        except Exception as e:
            e1 = e
            continue
    else:
        print("Error: Could not read config file with any supported encoding")
        print(f"Error reading config file: {e1}")
        print(f"Config file: {config_file}")
        sys.exit(1)
    
    # Validate required sections/keys
    if not config.has_section('Discord'):
        print("Error: Config file missing [Discord] section")
        sys.exit(1)
    
    if not config.has_option('Discord', 'webhookURL'):
        print("Error: Config file missing webhookURL in [Discord] section")
        sys.exit(1)
    
    webhook_url = config['Discord']['webhookURL'].strip()
    if not webhook_url:
        print("Error: webhookURL is empty in config file")
        sys.exit(1)
    
    return config

# Usage
config = load_config()
webhook_url = config['Discord']['webhookURL']
username    = config.get('Discord', 'username', fallback=appname)
userID      = config.get('Discord', 'userID',   fallback="")
enablePing  = int(config.get('Discord', 'enablePing', fallback=0))

dmsg = f" {status}" if status else ""
dmsg += f" sold={sold}" if sold else ""
dmsg += f" salesize={salesize}" if (not str.isdigit(salesize) or int(salesize)>1) else ""
dmsg += f" retries={retries}"   if (not str.isdigit(retries)  or int(retries)>0)  else ""
dmsg += f" <@{userID}>"         if (str.isdigit(userID) and enablePing) else ""

webhook = DiscordWebhook(url=webhook_url, username=username, content=dmsg)
response = webhook.execute()
