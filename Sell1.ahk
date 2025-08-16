#Requires AutoHotkey v2
#SingleInstance Force

; INSTRUCTIONS:
; - This is a script for AutoHotKey v2.  https://www.autohotkey.com/docs/v2/howto/Install.htm
; - when you're ready to start selling, switch the radio buttons on the gui from "Test" to "Sell"
; - since it's reading the screen colors, if it loses sync it'll just stop rather than going crazy
; - no need to tell it how many to sell, it'll empty your hold and stop
; - if there's a lag spike or the server loses a keypress, it'll verify it's still in the right place and retry (up to 3 times)
;   (the "retries=" on the popup is the total number of retries since you hit ^!F8), "try=" is how many of the 3 retries you're on
; - if you want an option to sell other size lots (like 2, or 8), edit the ^!F7 line below
; - you can get faster sales and better reliability by descending into the hangar before selling
;   since your game client doesn't have to think about all those other ships flying around
; - if you're having a hard time making this work well, AHK comes with WindowSpy to look at pixel locations and colors,
;   and you can edit %APPDATA%\config.ini to change locations of the pixels we're looking at, and the colors we're looking for
;   but you shouldn't need to do that, and I'd love it if you could let me know by filing an issue on GitHub
; - speed on my machine: 4.3sec/sale at 720tons, 2.7sec/sale at 10tons

#HotIf WinActive("ahk_class FrontierDevelopmentsAppWinClass")
^!F8::smallSales(1)
^!F7::smallSales(2)		; SmallSales will take any number you like, but keep it small or it'll be slow
^!F9:: Send("{" k.up " up}{" k.down " up}{" k.left " up}{" k.right " up}{" k.select " up}"), Reload(), SoundBeep(2000, 500)  ; Reload the script  [shamelessly stolen from OB]
^!F10::initButtons()	; ask where the buttons are, figure out the colors
Pause::togglePause		; make sure to be on the SELL COMMODITY screen when you un-pause
#HotIf 

k := {up: "w", down: "s", left: "a", right: "d", select: "Space", click: "LButton", cancel: "RButton"}	; see readKeysConfig() below to customize

;TODO: put version number in the config.ini, rename cSFocusDim to cSNoFocusDim
;TODO: simple log rotation
;TODO: track for each button/color/seconds tuple -- delay from keys sent to color seen, and retries, and display it in an optional debug window
;TODO: add an advisory in setup, to drop into the hangar for faster & more reliable sales
;TODO: figure out what's up with the reported cursor xy not matching the window

;logFileObj := FileOpen("ED-Sell1.log", "a")
;loggit := (str) => logFileObj.WriteLine(FormatTime(, "yyyyMMdd ddd HH:mm:ss> ") str)
;loggit("start`n`n")		; doesn't work, /sad  ;TODO or does it?
strRepeat := (string, times) => strReplace( format( "{:" times "}",  "" ), " ", string )
beepExit := () => (SoundBeep(523, 250), SoundBeep(500, 250), SoundBeep(523, 250))
beepDone := () => (SoundBeep(500, 250), SoundBeep(500, 50), SoundBeep(523, 1000))

debugMode := false
testMode := true		; set to true when you're getting set up, so we hit RMouse to cancel, rather than spacebar to actually sell the goods
PauseOperation := false
timing := {interKey: 125, keyDuration: 75, extraSellWait: 50, retryMult: 1, retries: 4}		; see readTimingConfig() below, to make timing more or less aggressive
edWin := {x: 0, y: 0, width: 0, height: 0, hwnd: 0}		; Elite Dangerous window

if (edWin.hwnd := WinExist("ahk_exe EliteDangerous64.exe")){
	WinActivate			; give ED focus, even though our window is always on top
	WinGetPos(&x, &y, &w, &h)
	edWin.x := x, edWin.y := y, edWin.width := w, edWin.height := h
} else {
	MsgBox("Elite Dangerous not running, please start the game and try again.")
	exitApp
}
activateEDWindow() {
	sleep 50
	WinActivate edWin
	sleep 50
}

; Configuration - use config.ini in %APPDATA% to store settings
config := {fileName: "config.ini", defaultSection: "Settings"}
initConfig() {
	config.appName := RegExReplace(A_ScriptName, "\.[^.]*$")  ; Remove extension
	config.dir := EnvGet("APPDATA") . "\" . config.appName
	if !DirExist(config.dir)
		DirCreate(config.dir)
	config.file := config.dir . "\" . config.fileName
	if !FileExist(config.file) {
		writeConfigVar("testMode", testMode ? "1" : "0")  ; store testMode as 1 or 0
	}
}
initConfig()

readConfigVar(key, fallback := "") {
	return IniRead(config.file, config.defaultSection, key, fallback)
}
writeConfigVar(key, value) {
	IniWrite(value, config.file, config.defaultSection, key)
}

readButtonConfig(btn){
	;buttonMsgBox(btn, btn.name " PREload`n")
	for propName in ["x", "y"]
		btn.%propName% := IniRead(config.file, btn.name, propName, 0)
	for propName in colorNames
		btn.HasProp(propname) && btn.%propName% := IniRead(config.file, btn.name, propName, 0x000000)
	buttonMsgBox(btn, btn.name " LOAD`n")
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
; Available keys are listed in https://www.autohotkey.com/docs/v2/KeyList.htm
; Detailed info on the format of config.ini is at https://www.autohotkey.com/docs/v2/lib/IniRead.htm
readKeysConfig() {	
	global k
	for keyName in ["up", "down", "left", "right", "select", "click", "cancel"] {
		k.%keyName% := IniRead(config.file, "EDkeys", keyName, k.%keyName%)
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
	}
}

; debugging convenience
buttonMsgBox(btn, msg := ""){
	for propName in ["name", "x", "y", "lum"]
		if (btn.HasProp(propName))
			msg := msg . propName . ": " . btn.%propName% . "`n"
	for propName in colorNames
		if (btn.HasProp(propName))
			msg := msg . propName . ": " . Format("{1:#06X}", btn.%propName%) . "`n"
	if (debugMode) {
		MsgBox(msg)
		activateEDWindow()
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

G.Add("Text", "Y+5 Section", "sold =")
GuiCtrlSold      := G.Add("Text", "X+3 ys", "0000")
GuiCtrlPaused    := G.Add("Text", "X+3 ys", "Starting up  ")

					G.Add("Text", "X9 Y+3 Section", "try=")
GuiCtrlTry       := G.Add("Text", "X+0 ys", "00")
					G.Add("Text", "X+5 ys", "retries=")
GuiCtrlRetries   := G.Add("Text", "X+0 ys", "0000")

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
	activateEDWindow()
}
setTestMode(mode){		; TODO use default value := 1
	GuiCtrlTestMode.Value := (mode ? 1 : 0)
	handleTestMode()
}

GuiCtrlWaitBtn   := G.Add("Text", "X9 Y+3 Section", "Wait for")
GuiCtrlWaitColor := G.Add("Text", "X+3 ys", "Wait for color")
GuiCtrlWaitSec   := G.Add("Text", "X+3 ys", "XX")

GuiCtrlSellTabColor    := G.Add("Text", "X9 Y+2 Section", "0xXXXXXX")
GuiCtrlSellButtonColor := G.Add("Text", "X+3 ys", "0xXXXXXX")

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
	SetKeyDelay 1000, 100
	activateEDWindow()
	result := MsgBox("To initialize this script (wiping the old config),`n`n"
		"open up a station's commodities market`n`n"
		"then click OK`n`n`n"
		"or . . . click CANCEL to abort", "Welcome to " A_ScriptName, "OKCancel Default2")
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
	buttonMsgBox(sellTab, "sellTab LATE`n")

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
	buttonMsgBox(sellButton, "sellButton LATE`n")
	setTestMode(true)			;might not already be true, if this isn't the first time
	writeButtonConfig(sellTab)
	writeButtonConfig(sellButton)
	initGui.Hide()
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
		"Enjoy your 1-ton selling adventures")
	return true
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
}

WaitForColorPS(x, y, c, msec){
  tmpx := 0, tmpy := 0
  Loop {
	if (PixelSearch(&tmpx, &tmpy, x, y, x, y, c, 5))
	  return true
	Sleep 50
  } Until ((msec -= 50) <= 0)
  return false
}

; TODO: rename this, remove the S1
; button, color name, seconds.  col is a string so we can display it in the UI
S1WaitForColor(btn, col, sec){
  GuiCtrlWaitBtn.Text         := btn.name
  GuiCtrlWaitColor.Text       := col
  GuiCtrlWaitSec.Text         := sec
  result := WaitForColorPS(btn.x, btn.y, btn.%col%, sec * 1000)
  GuiCtrlSellTabColor.Text    := PixelGetColor(sellTab.x, sellTab.y)
  GuiCtrlSellButtonColor.Text := PixelGetColor(sellButton.x, sellButton.y)
  sleep 50		; TODO remove this delay?
  return result
}

SendAndWaitForColor(msg, btn, col, sec, tries){
  thisTry := 0
  static retries := 0
  static oldBtn := ""
  static oldCol := ""
  loop {
	GuiCtrlTry.Text := ++thisTry
	if (thisTry>1)
		GuiCtrlRetries.Text := ++retries
	if (msg)
	  SendEvent msg
	if (S1WaitForColor(btn, col, (sec * thisTry * timing.retryMult))) {		; rather than delay X times (n=1..X) for s seconds, delay X times for n*s seconds
	  oldBtn := btn
	  oldCol := col
	  return true
	} 
	; if the old (==previous) pixel check fails, we can't try again
	if(!msg || !oldBtn || !oldCol || !S1WaitForColor(oldBtn, oldCol, 0))
	  return false
  } until (thisTry >= tries)
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

smallSales(SellBy){		; SellBy is the number of tons to sell at a time.  TODO needs a better name
  sold := 0
  GuiCtrlRetries := 0
  global PauseOperation
  SetKeyDelay timing.interKey, timing.keyDuration
  if !VerifyStartingPosition()
	return beepExit		; should be beepExit(), yes?
  sellCountStr := strRepeat("{" k.right "}", SellBy)
  while true {
	sellKey := (testMode) ? ("{" k.cancel "}") : ("{" k.select "}")								; testMode is true for testing, false for actually selling
	timekeeper(sold)
	if (WinExist("A") != edWin.hwnd) {															; if the ED window isn't on top, we can't do anything
		MsgBox("Looks like you want control of your computer back, so I'm stopping.")			; this doesn't seem to work, but the test is kicking us out, so I'm calling it a win
		break
	}
	; to differentiate them for debugging, each button/color/seconds tuple should be unique.  it's displayed on the 2nd-from-bottom line in the gui
	if (S1WaitForColor(sellButton, "cSFocusZero", 0)) {											; nothing left, we're done!
	  timekeeper("final")
	  return beepDone()
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
	if (!SendAndWaitForColor(sellKey, sellTab, "cSNoFocus", 4, timing.retries))					; sell and wait for the sell window to go away, revealing sellTab without the dimming
	  break
	if (!SendAndWaitForColor("{" k.select "}", sellTab, "cSFocusDim", 4, timing.retries))		; select the commodity from the list
	  break
	if PauseOperation {
	  timekeeper("pause")
	  GuiCtrlPaused.Text := "Paused"
	  while PauseOperation {
		sleep 1000
	  }
	  if !VerifyStartingPosition()
		return beepExit()
	  GuiCtrlPaused.Text := ""
	  timekeeper("resume")
	}
  }
  beepExit()
}

