Elite Dangerous helper script in [AutoHotKey V2](https://www.autohotkey.com/docs/v2/howto/Install.htm)
to sell one ton of goods at a time, for reasons.

## Features

- Peeps pixels to stay in sync with the ED UI.  Reacts immediately when the UI responds, doesn't waste time waiting for a timer.
- If it loses sync, it'll stop rather than wandering through the menu and selling your Corvette.
- If it thinks the only thing wrong is the game didn't see a keypress, it'll wait a bit and try again.
(It'll try a few times, except the SELL button it'll only try twice, to avoid selling your entire inventory at once.)
- Works with the "More Info" sidebar displayed or not.
- You don't need to have the cursor on the SELL button, just be on the SELL COMMODITY screen.
- Second hotkey for selling slightly larger lots (like 2-8)
- Pause key will pause operation
- Configurable timing settings: inter-keypress delay, keypress duration, timout scale factor
- Configurable UI navigation keys, if you've remapped WASD, etc

## Setup
When run for the first time, there'll be a short setup process, to account for different screensize, scaling, colors, etc.
It just needs you to click on a couple things.  Quick & painless.  Please do read everything carefully, and follow the instructions.

## GUI
On start, a small GUI will show command keys, and some timing and debug information.
Also links to config, log, and script directories.

## Operation notes

When you want to start selling:
- get onto the SELL COMMODITY screen
- (no need to be on the SELL button specifically)
- quantity should be something like "720/720"
- press Ctl-Alt-F8 to start selling 1 ton at a time

To pause, press Pause.  To resume (aka un-pause):
- get onto the SELL COMMODITY screen
- press Pause

You can get faster sales and better reliability by dropping into the station hangar,
since the client doesn't have so much work to do, tracking the other ships.
Going to solo mode may also help, depending on how crowded the station is.

If you have a few different commodities in your hold and wish to sell them all,
filter the commodities list to only show "in inventory", and start with the top one in the list.
After each sale, the script just selects the commodity the cursor is on.
If you're done with one commodity but have others, and the cursor happens to land there, it just keeps going.
Preventing this is more trouble than it's worth, so we're calling it a feature.
(If you don't wish to sell them all, you may be in for a surprise.)

## Logging
Log is %LocalAppData%\Sell1\app_DAY.log, rotates each weekday.  There's a link to it on the GUI.

At the end of a batch, it shows a summary broken down by each UI action -- key sent to ED,
which pixel it watched and what color it was waiting for, time spent, retries.
Gives some debugging data about the last few UI actions.  On failure, records the cause.

Very helpful for diagnosing problems, or improving the timing variables,
especially if you sell a small batch and set "minloglevel=0".

If something has gone horribly wrong with setup, there may be useful info in the console,
viewable with [DebugView](https://download.sysinternals.com/files/DebugView.zip).

## Configuration
Config file is %AppData%\Sell1\config.ini, there's a link to it on the GUI.
Edit it, save it, then reload the script with Ctl-Alt-F9.
Below are some config variables with their default values.

(warning: just use the "key=value" parts.  config.ini doesn't support comments, so don't cut'n'paste any line with comments on it.)
```
[Settings]
minLogLevel=1				; 0 - debug (logs ~15 lines per sale);  1 - important stuff and a summary at the end
logfileopenmode=a			; a - append to today's logfile;  w - clear out log file before each run
optionExitGameAtEnd=0		; 1 - show a checkbox on the GUI; click it to exit the game when this load is done
saleSize2ndKey=2			; Ctl-Alt-F7 will sell this many tons at a time
notifyProgram=""			; a string to be Run() when we're done selling
```

#### Keymap
These are the keys we use to navigate around the ED UI.
If you've modified your keymap, you'll need to describe your changes here.
Available key names are listed in https://www.autohotkey.com/docs/v2/KeyList.htm,
Detailed info on the format of config.ini is at https://www.autohotkey.com/docs/v2/lib/IniRead.htm
```
[EDkeys]					
up=w
down=s
left=a
right=d
select=Space
escape=Escape
click=LButton
cancel=RButton
```
If you want to pause with something besides the Pause button, you still need to edit the script (until I fix that...)
Look for the #HotIf section close to the top.

#### Timing
```
[Timing]
keyDelay=20			; time between keypresses
keyDuration=50		; how long to hold down each key
retryMult=1			; multiply the retry delay periods by this number
```
On my computer, these values are as low as I could get them while seeing very few retries.
If you want to push it faster, I suggest using a small batch (20 tons) of something cheap at your local station,
and watching the average times (in the log, the final summary section)
and retries (extra entries in attempts[], if they show up) for each button press vs previous tests.

If your computer is a bit sluggish and prone to the occasional lag spike before it recognizes a keypress,
the `retryMult` variable can lengthen your timeouts, so you don't wind up prematurely exiting the loop.
Try putting a [Timing] section in your config.ini that looks like this:
```
[Timing]
keyDelay=50
keyDuration=100
retryMult=5
```
If you're still having problems, double keyDelay and keyDuration until things work.
Once you get few (ideally zero) retries showing up in the log, try lowering `keyDelay`, then `keyDuration`.

#### RiskyRetryA and RiskyRetryB
```
[Timing]
riskyRetryA=2				; how many times do we try clicking on SELL?
riskyRetryB=1				; how many times do we try clicking on the commodity to go back to the SELL screen?
```
If you're feeling lucky, add these to your `[Timing]` section with values of 5, like me!
It *probably* won't sell everything at once.  But you definitely want to descend into the hangar to sell,
and selling in Solo mode probably isn't a bad idea.

So, the background: if we select (with {Space}) the SELL button, and nothing happens, what do we do?
Try selecting it a second time?  But if we try again a *third* time, possibly the computer was just sluggish for
a few seconds, and then it sees three {Space} characters, and selects the thing under the cursor three times --
first the SELL button, then the commodity you're selling to go back to the SELL screen, then the third one
sells your whole inventory.  So we can't try 3 times, we can only try twice.

The problem is even worse on the action after that, selecting the commodity to go back to its SELL COMMODITY screen.
When we hit {Space} to select the commodity the cursor is at, and nothing happens, do we try a second time?
If we do, maybe it's the same problem -- sluggish computer, which then wakes up and processes both {Space} keypresses.
The first selects your commodity, and the second sells your whole inventory.

If you use the default values, you're risking a single timeout causing the script to quit.  On the other hand,
if you set riskyRetryA and riskyRetryB to 5 like I do, you're risking a lag spike selling your whole inventory.

(I have an idea for how to improve this, but it's messy.)



## notifyProgram

If `Settings.notifyProgram` is set, it is Run(), and should probably be some kind of script.
A few environment variables are set, to provide a bit more information in your notification.

- `SELL1_STATUS`  A short string giving a general impression of how things went.
- `SELL1_SALESIZE`  How many tons are sold at a time.
- `SELL1_SOLD`  How many tons were sold.
- `SELL1_RETRIES`  How many times we timed out and tried again.

A `notify-stub.py` is included for testing purposes, which will log these variables to `%LocalAppData%\Sell1\notify.log`.
