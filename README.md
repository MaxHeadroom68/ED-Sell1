Elite Dangerous helper script in AutoHotKey v2 to sell one ton of goods at a time

Logging in %LocalAppData%\Sell1\app_DAY.log, rotates each weekday
Very helpful for diagnosing problems, especially if you sell a small batch and set "minloglevel=0".

Config in %AppData%\Sell1\config.ini, here are some things you might want to add:
(warning: just use the "key=value" parts.  config.ini doesn't support comments, so don't cut'n'paste any line with comments on it.)
[Settings]
minLogLevel=1				; 0 - debug (~15 lines per sale);  1 - important stuff and a summary at the end
logfileopenmode=w			; a - append to today's logfile;  w - clear out log file before each batch

							; these are the keys we use to navigate around the ED UI
[EDkeys]					; Available key names are listed in https://www.autohotkey.com/docs/v2/KeyList.htm
up=Up
down=Down
left=Left
right=Right
select=Space
escape=Escape
click=LButton
cancel=RButton
							; if you want to pause with something besides the Pause button, you still need to edit the script (until I fix that...)

[Timing]
keyDelay=20					; time between keypresses
keyDuration=50				; how long to hold down each key
retryMult=1					; multiply the retry delay periods by this number

If your computer is a bit sluggish and prone to the occasional lag spike before it recognizes a keypress, try putting a [Timing] section in your config.ini that looks like this:
[Timing]
keyDelay=50
keyDuration=100
retryMult=5