#Requires AutoHotkey v2
#SingleInstance Force
;#include Object2Str.ahk

; INSTRUCTIONS:
; - This is a script for AutoHotKey v2.  https://www.autohotkey.com/docs/v2/howto/Install.htm
; - config file is at %APPDATA%\Sell1\config.ini, log file is at %LOCALAPPDATA%\Sell1\app_DAY.log
; - If you've modified your keys, you may need to modify the #HotIf block below, and your config.ini file
;   See k{} below for a list of keys' default values, and readKeysConfig() below for details on config.ini
; - When you first run the script, there will be a brief setup process.  Please do read everything carefully
; - When you're ready to start selling, switch the radio buttons on the gui from "Test" to "Sell"
; - Since it's reading the screen colors, if it loses sync it'll just stop rather than going crazy
; - No need to tell it how many to sell, it'll empty your hold and stop
; - If you have a few different commodities in your hold and wish to sell them all,
;   filter the commodities list to only show "in inventory", and start with the top one in the list
; - If there's a lag spike or the server loses a keypress, it'll verify it's still in the right place and retry a few times
;   (the "retries=" on the popup is the total number of retries since you hit ^!F8), "try=" is how many of the 3 retries you're on
; - If you want an option to sell other size lots (like 2, or 8), edit the ^!F7 line below
; - You can get faster sales and better reliability by descending into the hangar before selling
;   since your game client doesn't have to think about all those other ships flying around
; - in the [Settings] section of config.ini, add "optionExitGameAtEnd=1" if you want a checkbox that'll log out of the game when we're done selling a load
; - If you're having a hard time making this work well, AHK comes with WindowSpy to look at pixel locations and colors,
;   and you can edit %APPDATA%\APPNAME\config.ini to change locations of the pixels we're looking at, and the colors we're looking for
;   but you shouldn't need to do that, and I'd love it if you could let me know by filing an issue on GitHub
; - Speed on my machine: 4.3sec/sale at 780tons, 2.9sec/sale at 10tons

#HotIf WinActive("ahk_class FrontierDevelopmentsAppWinClass")
^!F8::smallSales(1)
^!F7::smallSales(2)		; SmallSales will take any number you like, but keep it small or it'll be slow
^!F9:: Send("{" k.up " up}{" k.down " up}{" k.left " up}{" k.right " up}{" k.select " up}"), Lw("Reload"), SoundBeep(523, 150), Reload()  ; Reload the script  [shamelessly stolen from OB]
^!F10::initButtons()	; ask where the buttons are, figure out the colors
Pause::togglePause()	; make sure to be on the SELL COMMODITY screen when you un-pause
#HotIf 

k := {up: "w", down: "s", left: "a", right: "d", select: "space", escape:"escape", click: "LButton", cancel: "RButton"}	; see readKeysConfig() below to customize

;TODO: put version number in the config.ini, rename cSFocusDim to cSNoFocusDim
;TODO? write default keys into config.ini if they're not already there, to make it easier to change them?
;TODO? adaptively adjust timing based on frequency of retries, so it gets faster as it learns the timing; only active in testMode, if a configvar is set
;TODO: make the input keys (Pause, ^!F8, etc) configurable in config.ini, so you can change them to something else if you like.  How to do that without sacrificing readability?
;TODO: figure out what's up with the reported cursor xy not matching the window

strRepeat := (string, times) => strReplace( format( "{:" times "}",  "" ), " ", string )
beepHello := () => (SoundBeep(330,120), Sleep(30), SoundBeep(660,100), Sleep(40), SoundBeep(440,150), Sleep(20), SoundBeep(494,120))
beepConfigure := () => (SoundBeep(523,180), Sleep(40), SoundBeep(659,160), Sleep(50), SoundBeep(784,220))
beepStart := () => (SoundBeep(494,200), Sleep(10), SoundBeep(415,150))
beepSuccess := () => (SoundBeep(523,300), Sleep(80), SoundBeep(523, 150), Sleep(5), SoundBeep(784,1000))
beepFailure := () => (SoundBeep(294,400), Sleep(150), SoundBeep(277,500), Sleep(180), SoundBeep(262,500), Sleep(180), SoundBeep(247,1200))
Lx := (msg) => OutputDebug(A_ScriptName " " msg)				; log truly heinous errors to the console.  View with DebugView from MS
Lx("uhhh, everything's under control, situation normal")		; script starting up.  (classical reference)

debugMode := false			; used for random things during development
testMode := true			; set to true when you're getting set up, so we hit RMouse to cancel, rather than spacebar to actually sell the goods
PauseOperation := false
timing := {interKey: 125, keyDuration: 75, extraSellWait: 50, retryMult: 1, retries: 4}		; see readTimingConfig() below, to make timing more or less aggressive
edWin := {x: 0, y: 0, width: 0, height: 0, hwnd: 0}											; Elite Dangerous window

if (edWin.hwnd := WinExist("ahk_exe EliteDangerous64.exe")){
	WinActivate			; give ED focus, even though our window is always on top
	WinGetPos(&x, &y, &w, &h)
	edWin.x := x, edWin.y := y, edWin.width := w, edWin.height := h
	beepHello()
} else {
	beepFailure()
	MsgBox("Elite Dangerous not running, please start the game and try again.")
	exitApp
}
activateEDWindow() {
	sleep 50
	WinActivate edWin
	sleep 50
}

; Configuration - store settings in %APPDATA%\SCRIPTNAME\config.ini
config := {fileName:"config.ini", defaultSection:"Settings", minLogLevel:1, optionExitGameAtEnd:0} ;TODO: , version"0.3.0", prevVer:""}
initConfig() {
	config.appDir := A_ScriptDir
	config.appName := RegExReplace(A_ScriptName, "\.[^.]*$")  ; Remove extension
	config.dir := EnvGet("APPDATA") . "\" . config.appName
	if !DirExist(config.dir)
		DirCreate(config.dir)
	config.file := config.dir . "\" . config.fileName
	if !FileExist(config.file) {
		writeConfigVar("testMode", testMode ? "1" : "0")  ; store testMode as 1 or 0
	}
	openMode := "a"  ; open logfile in append mode by default
	;openMode := "w"  ; during testing, to keep things tidy, maybe we want to overwrite the log each time
	localAppData := EnvGet("LocalAppData") || EnvGet("TEMP") || A_Temp
	config.logdir := localAppData "\" config.appName
	if !DirExist(config.logdir)
		DirCreate(config.logdir)
	config.logFile := config.logdir "\app_" FormatTime(A_Now, "ddd") ".log"  ; Log file named with the current weekday
	if FileExist(config.logFile) && DateDiff(A_Now, FileGetTime(config.logFile, "M"), "Days") > 2
		openMode := "w"  ; If the log file is older than 2 days, overwrite it
	config.logHandle := FileOpen(config.logFile, openMode)  ; Open log file for appending
	config.minLogLevel         := readConfigVar("minLogLevel", config.minLogLevel)
	config.optionExitGameAtEnd := readConfigVar("optionExitGameAtEnd", config.optionExitGameAtEnd)
}
initConfig()

LogLevels := Map("debug", 0, "info", 1, "warn", 2, "error", 3)
LogMsg(level, message) {
	global config, LogLevels
	if !config.logHandle || !LogLevels.Has(level) || LogLevels[level] < config.minLogLevel
        return
	timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss") . "." . Format("{:03d}", Mod(A_TickCount, 1000))
    logEntry := timestamp " " StrUpper(level) " " message
    try {
        config.logHandle.WriteLine(logEntry)
		config.logHandle.Read(0) ; Flush the buffer to the log file immediately.  (there is no Flush() in v2)
    } catch Error as e {
        Lx("LOG ERROR: " e.message " - " logEntry)		; Fallback: at least show in console if file write fails.  NB: DebugView from MS
    }
}
LogMsg("info", "Script started: " A_ScriptName)
Ld := (msg) => LogMsg("debug", msg)
L  := (msg) => LogMsg("info", msg)
Lw := (msg) => LogMsg("warn", msg)
Le := (msg) => LogMsg("error", msg)

readConfigVar(key, fallback := "") {
	return IniRead(config.file, config.defaultSection, key, fallback)
}
writeConfigVar(key, value) {
	IniWrite(value, config.file, config.defaultSection, key)
}

readButtonConfig(btn){
	for propName in ["x", "y"]
		btn.%propName% := IniRead(config.file, btn.name, propName, 0)
	for propName in colorNames
		btn.HasProp(propname) && btn.%propName% := IniRead(config.file, btn.name, propName, 0x000000)
}
writeButtonConfig(btn){
	props := ""
	for propName in ["x", "y"]
		props := props . propName "=" btn.%propName% "`n"
	for propName in colorNames
		if (btn.HasProp(propName))
			props := props . propName "=" Format("{1:#06X}", btn.%propName%) "`n"
	IniWrite(props, config.file, btn.name)
}
zeroButton(btn){					; zero the button coordinates & colors
	btn.x := btn.y := btn.val := btn.lum := 0
	for i in colorNames
		btn.HasProp(i) && btn.%i% := 0x000000
	return btn
}
buttonsAreInitialized(){
	return (sellTab.x && sellButton.x)
}

; If you use Dvorak/Colemak/etc, you can change the keys (and mouse buttons) we use to navigate around the UI
; In %APPDATA%\Sell1\config.ini add a line "[EDkeys]" to start the section, then add lines like "up=w", "down=s", etc.
; See the definition of k{} (near the top of this file) for the default key names and values
; Available keys are listed in https://www.autohotkey.com/docs/v2/KeyList.htm
; Detailed info on the format of config.ini is at https://www.autohotkey.com/docs/v2/lib/IniRead.htm
readKeysConfig() {	
	global k
	for keyName in ["up", "down", "left", "right", "select", "escape", "click", "cancel"] {
		k.%keyName% := IniRead(config.file, "EDkeys", keyName, k.%keyName%)
		Ld("readKeysConfig() k=" keyName " val=" k.%keyName%)
	}
}

; in %APPDATA%\Sell1\config.ini, create a [Timing] section, then you can set:
; interkey			time between key presses
; keyDuration		how long to hold down each key
; extraSellWait		extra wait before the sell button is pressed
; retryMult			multiply the hard-coded delay between retries by this factor, default is 1
; retries			number of retries to do before giving up
readTimingConfig() {
	global timing
	for keyName in ["interKey", "keyDuration", "extraSellWait", "retryMult", "retries"] {
		timing.%keyName% := IniRead(config.file, "Timing", keyName, timing.%keyName%)
		Ld("readTimingConfig() variable=" keyName " val=" k.%keyName%)
	}
}

colorNames := ["cSFocus", "cSNoFocus", "cSFocusDim", "cSFocusZero", "cSNoFocusZero"]
sellTab := {				; coordinates and colors for the SELL tab in the commodities market
	name: "sellTab", x: 0, y: 0, val: 0, lum: 0,
	cSFocus:	0,			; colorSelectedFocus		-- focus is on the sell tab
	cSNoFocus:	0,			; colorSelectedNoFocus		-- selected (vs buy) but focus is elsewhere
	cSFocusDim:	0			; colorSelectedFocusDim	-- selected, not in focus, and sell-item overlay dims this layer  (yup, should be named cSNoFocusDim.  oh well, too late now)
	; good values for 1920x1080: x: 180, y: 420
	; values for stock UI colors: cSFocus: 0xFF6F00, cSNoFocus: 0x4E2302, cSFocusDim: 0x1F0E01
	; texture means we gotta find the brightest pixel, look at 4 vertically stacked pixels for the brightest one
}
sellButton := {				; coordinates and colors for the SELL button in the commodities market
	name: "sellButton", x: 0, y: 0, val: 0, lum: 0,
	cSFocus:		0,		; colorSelectedFocus		-- focus is on button, amount is >0
	cSNoFocus:		0,		; colorSelectedNoFocus		-- focus is elsewhere, amount is >0
	cSFocusZero:	0,		; colorSelectedFocusZero	-- focus is on button, amount is zero
	cSNoFocusZero:	0		; colorSelectedNoFocusZero	-- focus is elsewhere, amount is zero
	; good values for 1920x1080: x: 990, y: 580
	; values for stock UI colors: cSFocus: 0xFF6F00, cSNoFocus: 0x210E00, cSFocusZero: 0xC2C2C2, cSNoFocusZero: 0x191919
}
readButtonConfig(sellTab)
readButtonConfig(sellButton)
if (!buttonsAreInitialized()) {
	testMode := true
	writeConfigVar("testMode", testMode)
}

G := Gui("AlwaysOnTop -MaximizeBox -MinimizeBox", config.appName)
G.Add("Text", "X9 Y+8 Section", "Ctl-Alt-F8 to sell 1 ton lots")
G.Add("Text", "Y+2", "Ctl-Alt-F7 to sell 2 ton lots")
G.Add("Text", "Y+2", "Ctl-Alt-F9 to reload script")
G.Add("Text", "Y+2", "Ctl-Alt-F10 to wipe config")
G.Add("Text", "Y+2", "Pause to pause/resume")

testMode := Integer(readConfigVar("testMode", 1)) ? 1 : 0		; for testing mode, we hit RMouse to cancel rather than Space to sell
{
	notTestMode := !testMode										; next line can't use an expression, gotta be a variable.  /sigh
	G.Add("Radio", "X9 Y+7 Section Checked" notTestMode, "Sell").OnEvent("Click", handleTestMode)
}
GuiCtrlTestMode := G.Add("Radio", "vtestMode X+3 ys Checked" testMode, "Test")			
GuiCtrlTestMode.OnEvent("Click", handleTestMode)
handleTestMode(*) {												; whichever radio button is clicked, we read the value of GuiCtrlTestMode
	global testMode
	testMode := (GuiCtrlTestMode.Value ? 1 : 0)					; set global
	writeConfigVar("testMode", testMode ? "1" : "0")			; write to config
	Ld("handleTestMode() testMode: " testMode)
	activateEDWindow()
}
setTestMode(mode := 1){
	GuiCtrlTestMode.Value := (mode ? 1 : 0)
	handleTestMode()
}

G.Add("Text", "X9 Y+5 Section", "sold =")
GuiCtrlSold      := G.Add("Text", "X+3 ys", "0000")
GuiCtrlPaused    := G.Add("Text", "X+3 ys", "Starting up  ")

					G.Add("Text", "X9 Y+3 Section", "try=")
GuiCtrlTry       := G.Add("Text", "X+0 ys", "00")
					G.Add("Text", "X+5 ys", "retries=")
GuiCtrlRetries   := G.Add("Text", "X+0 ys", "0000")

G.Add("Link", "X9 Y+3 Section",  '<a href="' config.dir    '">Config</a>')
G.Add("Link", "X+12 ys",         '<a href="' config.logdir '">Log</a>')
G.Add("Link", "X+12 ys",         '<a href="' config.appdir '">Script</a>')

GuiCtrlWaitBtn   := G.Add("Text", "X9 Y+3 Section", "Wait for")
GuiCtrlWaitColor := G.Add("Text", "X+3 ys", "Wait for color")
GuiCtrlWaitSec   := G.Add("Text", "X+3 ys", "XX")

GuiCtrlSellTabColor    := G.Add("Text", "X9 Y+2 Section", "0xXXXXXX")
GuiCtrlSellButtonColor := G.Add("Text", "X+3 ys", "0xXXXXXX")
if (config.optionExitGameAtEnd) {
	GuiCtrlExitGameAtEnd := G.Add("CheckBox", "X9 Y+3", "Exit Game At End?")
	GuiCtrlExitGameAtEnd.OnEvent("Click", (*) => activateEDWindow())
}

{	; get saved GUI position, or default to bottom-left of the ED window
	x := y := w := h := 0
	G.GetPos(&x, &y, &w, &h)
	guiX := Integer(readConfigVar("guiX", edWin.x +5))
	guiY := Integer(readConfigVar("guiY", edWin.y +edWin.height -220))
}
G.Show("x" . guiX . " y" . guiY)

OnMessage(0x0232, SaveGUIPosition)				; WM_EXITSIZEMOVE	Monitor for window move completion
SaveGUIPosition(wParam, lParam, msg, hwnd) {	; Save GUI position when move/resize is complete
	if (hwnd != G.Hwnd)
		return false
	G.GetPos(&x, &y)
	writeConfigVar("guiX", x)
	writeConfigVar("guiY", y)
}

while (!buttonsAreInitialized()) {
	if !initButtons() {		; if the user clicks cancel, we don't want to do anything
		MsgBox("Initialization cancelled.  Exiting script.")
		exitApp
	}
	if (!buttonsAreInitialized())
		MsgBox("Initialization failed.  Please try again.")
}
activateEDWindow()

readKeysConfig()

; Luminance = (0.2126 * R + 0.7152 * G + 0.0722 * B)
requestMouseXY(btn, msg := "") {
	activateEDWindow()
	KeyWait "LButton", "D"
	activateEDWindow()
	MouseGetPos(&x, &y)
	sleep 200
	MouseMove(edWin.width/2, edWin.height-30)	
	btn.x := x
	for i in [0, 1, -1, 2] {
		val := PixelGetColor(btn.x, y+i)
		lum := round(0.2126 * ((val >> 16) & 0xFF) + 0.7152 * ((val >> 8) & 0xFF) + 0.0722 * (val & 0xFF))
		if (lum > btn.lum) {		; find the brightest pixel in the 4 pixels vertically stacked
			btn.y := y+i
			btn.val := val
			btn.lum := lum
		}
	}
	return btn
}

initButtons(){
	beepConfigure()
	L("configuration started")
	SetKeyDelay 1000, 100
	activateEDWindow()
	result := MsgBox("To initialize this script (wiping the old config),`n`n"
		"open up a station's commodities market`n`n"
		"then click OK`n`n`n"
		"or . . . click CANCEL to abort`n`n`n"
		"(NOTE:  If you've modified your menu-navigation keys`n"
		"    (wasd, space, mouse buttons),`n"
		"    there are instructions in the comments at the top of the script.`n"
		"    Abort now, read them, come back when you're done)`n`n"
		, "Welcome to " A_ScriptName, "OKCancel Default2")
	if (result = "Cancel"){
		return false
	}
	MsgBox("I'll ask you to click certain places`n"
		"so I can find out where the buttons are`n`n"
		"And I'll use the WASD keys to navigate around a bit`n"
		"so I can find out what the colors mean`n`n"
		"And I'll move your mouse out of the way.`n`n"
		"But don't worry, I won't buy or sell anything`n"
		"(at least, not intentionally...)`n`n"
		"so please don't move your mouse`n"
		"or click on anything`n"
		"except when I ask you to.`n`n"
		"Click OK when you're ready to start")
	initGui := Gui("+Resize AlwaysOnTop", "Show me the SELL tab")
	initGui.SetFont("s12")
	txt := initGui.Add("Text", "", ;"w400",
		"Find the SELL tab, below the BUY tab`n"
		"	on the left side of the E:D marketplace window`n`n"
		"Find an open spot of color, towards the bottom-right corner`n"
		"    (...but not aaaalllll the way to the right.  `n"
		"     Maybe you've noticed the bright stripe along the`n"
		"     right side when it's selected but doesn't have focus?`n"
		"     Not in there, I'll get confused.)`n`n"
		"	Go ahead and click there now`n")
	initGui.Show("X" . round(edWin.X + edWin.width/2 - 400/2)
		" Y" . round(edWin.y + edWin.height/6))
	activateEDWindow()
	requestMouseXY(zeroButton(sellTab))
	sellTab.cSFocus := PixelGetColor(sellTab.x, sellTab.y)
	SendEvent("{" k.right "}")
	sellTab.cSNoFocus := PixelGetColor(sellTab.x, sellTab.y)
	SendEvent("{" k.select "}")
	sellTab.cSFocusDim := PixelGetColor(sellTab.x, sellTab.y)
	sleep 1000
	SendEvent("{" k.cancel "}")

	initGui.Hide()
	MsgBox("So far so good.  Now, click on a commodity`n"
		"that you have AT LEAST ONE TON OF in your ship's hold`n"
		"so you're looking at the SELL COMMODITY screen`n`n"
		"and get set up to sell ZERO TONS of it`n"
		'(so the amount shows something like "0/720" )`n`n'
		'Also, open up the "More Info" sidebar, if you have it closed.`n'
		"(We'll choose a pixel that'll work later if it's open or closed)`n`n"
		"Click OK when you're ready")
	activateEDWindow()
	initGui.Title := "Show me the SELL button"
	txt.Text := ('selling ZERO TONS, right?  "0/nnn" or similar?`n`n'
	"Find an open spot of color (well, probably grayish)`n"
		"    towards the upper-right corner of the SELL button`n`n"
		"Go ahead and click there now")
	initGui.Show("X" . round(edWin.x + edWin.width/2 - 400/2)
		" Y" . round(edWin.y + edWin.height/20))
	initGui.Flash()
	activateEDWindow()
	requestMouseXY(zeroButton(sellButton))
	initGui.Flash(false)
	sellButton.cSFocusZero := PixelGetColor(sellButton.x, sellButton.y)
	SendEvent("{" k.up "}")
	sellButton.cSNoFocusZero := PixelGetColor(sellButton.x, sellButton.y)
	SendEvent("{" k.right "}")
	sellButton.cSNoFocus := PixelGetColor(sellButton.x, sellButton.y)
	SendEvent("{" k.down "}")
	sellButton.cSFocus := PixelGetColor(sellButton.x, sellButton.y)
	sleep 1000
	SendEvent("{" k.cancel "}")
	setTestMode(true)			;might not already be true, if this isn't the first time
	writeButtonConfig(sellTab)
	writeButtonConfig(sellButton)
	initGui.Hide()
	L("configuration finished")
	MsgBox("You're all set up!`n`n"
		"See the tiny " config.appName " window?  Feel free to move it.`n"
		"You're in `"Test`" mode now, so you can try out selling with no risk.`n"
		'When you want to start selling for real, switch from "Test" to "Sell".`n'
		"(But not while I'm running, that'll get messy.  Hit Pause or Ctl-Alt-F9 first.)`n`n"
		"Remember, when you want to start selling:`n"
		"- get onto the SELL COMMODITY screen`n"
		'- quantity should be something like "720/720"`n'
		"- press Ctl-Alt-F8 to start selling 1 ton at a time`n`n"
		"To pause, press Pause.  To resume (aka un-pause):`n"
		"- get onto the SELL COMMODITY screen`n"
		"- press Pause.`n`n"
		"Hint: for speed & reliability, drop into the hangar`n"
		"    Solo mode may also help.`n`n"
		"Enjoy your 1-ton selling adventures")
	return true
}

; keep some statistics about each of the action steps, so we can see how long they take, how often they retry or fail, etc
actionStats := Map()							; map of button name, color name, seconds => total duration, min, max, count attempts 1..N
actionLast := Map()								; map of button name, color name, seconds => duration, last time we logged this action, failMsg, attempts
actionIds := Array()							; the actions we've seen, in the order we first saw them
prevAction := {id: "", tick: 0, attempts:0, PSwaits:0}		; the last action we logged, when (in msec since reboot), and how many times we've tried it
logAction(btn, col, sec, failMsg:=""){
	id := (btn ? btn.name : "") "-" col "-" sec, tick := A_TickCount
	Ld("LogAction() id=" id " failMsg: " failMsg)
	if (prevAction.id) {
		if !actionStats.Has(prevAction.id) {									; if this tuple hasn't been seen before, initialize it
			actionStats[prevAction.id] := {duration:0, min:0, max:0, attempts:Array()}
			actionStats[prevAction.id].attempts.Default := 0					; so we can increment elements that haven't been set yet
			actionIds.Push(prevAction.id)										; add id to a list of ids, so we can iterate over it later
		}
		duration := tick - prevAction.tick
		if (duration < 1 || duration > 3600000) {								; a duration over an hour, or not >0, is probably overflow (happens every 42 days) or a bug
			Lw("logAction() suspicious duration=" duration " for id=" prevAction.id)	; log a warning if duration is suspiciously long or short
			duration := 0
		}
		stat := actionStats[prevAction.id]										; shorthand for the actionStats entry for this action
		stat.attempts.Length := Max(stat.attempts.Length, prevAction.attempts)	; make sure attempts[] is big enough)
		loop prevAction.attempts {												; bump those elements of attempts[] that we hit
			stat.attempts[A_Index]++
		}
		if (duration && (prevAction.attempts = 1)) {							; we only collect timing stats on successful first tries
			stat.duration += duration
			stat.min := ((stat.min = 0) ? duration : Min(stat.min, duration))
			stat.max := Max(stat.max, duration)
		}
		actionLast[prevAction.id] := {duration:duration, time:prevAction.tick, failMsg:failMsg, attempts:prevAction.attempts, PSwaits:prevAction.PSwaits}
	}
	prevAction.id := id, prevAction.tick := tick, prevAction.attempts := 1, prevAction.PSwaits := 0		; record the just-started action in prevAction
}
logActionRetry(){
	global prevAction
	prevAction.attempts++
	Lw("logActionRetry() id=" prevAction.id " attempts=" prevAction.attempts)
}
logActionFinal(){
	idlen := 0
	for id in actionIds
		idlen := Max(idlen, StrLen(id))
	L("summary statistics:")
	for id in actionIds {
		stat := actionStats[id]
		retries := (stat.attempts.Length>1) ? stat.attempts[2] : 0		; we should be able to use the default value of attempts[2] (aka 0) directly, but it threw an error, so...
		msg := "id=" Format("{:-" idLen+1 "}", id) "avg=" Format("{:i}", round(stat.duration / (stat.attempts[1] - retries))) .			; avg only counts successful first tries
			" duration=" stat.duration " min=" stat.min " max=" stat.max " attempts=["
		loop stat.attempts.Length {
			msg .= (A_Index>1 ? ", " : "") . stat.attempts[A_Index]
		}
		msg .= "]"
		L(msg)
	}
	L("last actions:")
	for id in actionIds {
		al := actionLast[id]
		L("time=" al.time " id=" Format("{:-" idLen+1 "}", id) " duration=" al.duration " msg='" al.failMsg "' attempts=" al.attempts " PSwaits=" al.PSwaits)
	}
}
logActionPause(mode) {
	static pauseTime := 0
	if (mode = "pause")
		pauseTime := A_TickCount
	if (mode = "resume") && pauseTime && ((A_TickCount - pauseTime) > 0)
		prevAction.tick += (A_TickCount - pauseTime)	; don't count paused time against the action duration
}

mmssTime(t){			; time in milliseconds, returns a string in MMmSSs format, or SS.msecs format if t < 60 seconds
	if (t < 60000) {
		return Format("{1:.4f}", t/1000)
	}
	secs := Round(t / 1000)
	return Format("{1:02i}m{2:02i}s", secs / 60, Mod(secs, 60))
}
timekeeper(mode){							; not critical to operation, just a little monitoring
	static startTime := 0
	static pauseTime := 0
	Ld("timekeeper() mode: " mode)
	if (mode = "pause") {
		pauseTime := A_TickCount
	} else if (mode = "resume") {
		startTime += (A_TickCount - pauseTime)
	} else if (mode = "final") {
		GuiCtrlPaused.Text := mmssTime(A_TickCount - startTime)
	} else if (!mode){
		startTime := A_TickCount
	} else {
		GuiCtrlPaused.Text := mmssTime((A_TickCount - startTime) / mode)
	}
}

togglePause(){
  global PauseOperation
  PauseOperation := !PauseOperation
  PauseOperation ? (GuiCtrlPaused.Text := "Pausing") : ""
  L("togglePause() PauseOperation: " PauseOperation)
}

WaitForColorPS(x, y, c, msec){
  tmpx := 0, tmpy := 0
  waitSize := 10
  Loop {
	if (PixelSearch(&tmpx, &tmpy, x, y, x, y, c, 5))
	  return true
	Sleep(waitSize)
	prevAction.PSwaits++
  } Until ((msec -= waitSize) <= 0)
  return false
}

; button, color name, seconds.  col is a string so we can display it in the UI
WaitForColor(btn, col, sec){
  GuiCtrlWaitBtn.Text         := btn.name
  GuiCtrlWaitColor.Text       := col
  GuiCtrlWaitSec.Text         := sec
  result := WaitForColorPS(btn.x, btn.y, btn.%col%, sec * 1000)
  GuiCtrlSellTabColor.Text    := PixelGetColor(sellTab.x, sellTab.y)
  GuiCtrlSellButtonColor.Text := PixelGetColor(sellButton.x, sellButton.y)
  sleep 50		; TODO remove this delay?
  return result
}

SendAndWaitForColor(msg, btn, col, sec, maxAttempts){
  thisTry := 0
  static retries := 0
  static oldBtn := ""
  static oldCol := ""
  logAction(btn, col, sec)
  loop {
	GuiCtrlTry.Text := ++thisTry
	if (thisTry>1) {
		GuiCtrlRetries.Text := ++retries
		logActionRetry()
	}
	if (msg)
	  SendEvent msg
	if (WaitForColor(btn, col, (sec * thisTry * timing.retryMult))) {		; rather than delay X times (n=1..X) for s seconds, delay X times for n*s seconds
	  oldBtn := btn
	  oldCol := col
	  return true
	} 
	; if the old (==previous) pixel check fails, we can't try again
	if(!msg || !oldBtn || !oldCol || !WaitForColor(oldBtn, oldCol, 0)) {
		logAction(btn, col, sec, "I_GOT_CONFUSED")
		return false
	}
  } until (thisTry >= maxAttempts)
  logAction(btn, col, sec, "TOO_MANY_RETRIES")
  return false
}

VerifyStartingPosition(){
  if (!buttonsAreInitialized()) {
	MsgBox("This shouldn't happen.  Time to wipe the config and start over.`n"
	  "Delete " config.file " and restart the script.", "How'd you get here?")
	return false
  }
  MouseMove(edWin.width/2, edWin.height-30)							; put the mouse on the bottom of the ED window, but out of the way
  if (!SendAndWaitForColor("", sellTab, "cSFocusDim", 1, 0))		; gotta start on the "SELL COMMODITY screen" selling your item
	return false
  ; move the cursor to the sell button, then add 1 to the quantity, then move the cursor back to the sell button
  SendEvent("{" k.down "}{" k.down "}{" k.left "}{" k.left "}{" k.down "}{" k.up "}{" k.up "}{" k.right "}{" k.down "}")
  return true
}

smallSalesOnExit(){
	Ld("smallSalesOnExit() config.optionExitGameAtEnd=" config.optionExitGameAtEnd " GuiCtrlExitGameAtEnd.Value=" GuiCtrlExitGameAtEnd.Value)
	if (GuiCtrlExitGameAtEnd.Value){
		SetKeyDelay 2000, 200
		SendEvent("{" k.escape "}{" k.up "}{" k.select "}{" k.right "}{" k.select "}")		;exits the game commodities or sell screen
		ExitApp()				; no point in sticking around -- after the game exits our hwnd is invalid
	}
}

smallSales(SellBy){		; SellBy is the number of tons to sell at a time.  TODO needs a better name
  sold := 0
  GuiCtrlRetries := 0
  global PauseOperation
  SetKeyDelay timing.interKey, timing.keyDuration
  if !VerifyStartingPosition()
	return beepFailure()
  beepStart()
  sellCountStr := strRepeat("{" k.right "}", SellBy)
  while true {
	sellKey := (testMode) ? ("{" k.cancel "}") : ("{" k.select "}")								; testMode is true for testing, false for actually selling
	timekeeper(sold)
	if (WinExist("A") != edWin.hwnd) {															; if the ED window isn't on top, we can't do anything
		Lw("Looks like you want control of your computer back, so I'm stopping")
		MsgBox("Looks like you want control of your computer back, so I'm stopping.")			; this doesn't seem to work, but the test is kicking us out, so I'm calling it a win
		break
	}
	; to differentiate them for debugging, each button/color/seconds tuple should be unique.  it's displayed on the 2nd-from-bottom line in the gui
	if (WaitForColor(sellButton, "cSFocusZero", 0)) {											; nothing left, we're done!
	  timekeeper("final")
	  logAction("", "", 0, "successful run")													; write the final action to the log
	  logActionFinal()																			; write the summary statistics to the log
	  smallSalesOnExit()
	  return beepSuccess()
	}
	if (!SendAndWaitForColor("", sellButton, "cSFocus", 4, 0))									; verify we're on the sell button, and set the "previous" button/color for the next SendAndWaitForColor
	  break
	if (!SendAndWaitForColor("{" k.up " down}", sellButton, "cSNoFocus", 4, timing.retries))	; cursor up, leave the key pressed  ; technique mentioned in LYR discord.  saves 0.46 seconds per sale at 720t, or 2m45s for a whole load
	  break
	if (!SendAndWaitForColor("{" k.left " down}", sellButton, "cSNoFocusZero", 10, timing.retries))		; cursor left, leave the key pressed, alllll the way to zero
	  break
	SendEvent("{" k.left " up}{" k.up " up}")													; release left & up.  we can't use SendAndWaitForColor here, because nothing changes color
	sleep timing.extraSellWait					  												; gets its own sleep, because I was having trouble with the next key being seen
	if (!SendAndWaitForColor(sellCountStr, sellButton, "cSNoFocus", 5, timing.retries))			; cursor right for the number we want to sell; needs a different timeout from the previous SellButton/colorSelectedNoFocus
	  break
	if (!SendAndWaitForColor("{" k.down "}", sellButton, "cSFocus", 5, timing.retries))			; down to the sell button; needs a different timeout from the previous SellButton/colorSelectedFocus
	  break						
	GuiCtrlSold.Text := (sold += SellBy)
	if (!SendAndWaitForColor(sellKey, sellTab, "cSNoFocus", 15, Max(2,timing.retries)))			; sell and wait for the sell window to go away, revealing sellTab without the dimming.  only try twice; don't sell the whole hold if there's a server burp.  that's why the timeout is so long
	  break
	if (!SendAndWaitForColor("{" k.select "}", sellTab, "cSFocusDim", 4, timing.retries))		; select the commodity from the list
	  break
	if PauseOperation {
	  timekeeper("pause"), logActionPause("pause"), GuiCtrlPaused.Text := "Paused"
	  while PauseOperation {
		sleep 1000
	  }
	  if !VerifyStartingPosition()
		break
	  timekeeper("resume"), logActionPause("resume"), GuiCtrlPaused.Text := ""
	}
  }
  logActionFinal()		; write the summary statistics to the log.  something in SendAndWaitForColor() failed, so logAction() already got called with a failure message
  smallSalesOnExit()
  beepFailure()
}

