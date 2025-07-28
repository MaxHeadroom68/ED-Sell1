#Requires AutoHotkey v2
#SingleInstance Force

;logFileObj := FileOpen("ED-AHK.log", "a")
;loggit := (str) => logFileObj.WriteLine(FormatTime(, "yyyyMMdd ddd HH:mm:ss > ") str)
;loggit "start`n`n"		; doesn't work, /sad
strRepeat := (string, times) => strReplace( format( "{:" times "}",  "" ), " ", string )
beepExit := () => (SoundBeep(523, 250), SoundBeep(500, 250), SoundBeep(523, 250))
beepDone := () => (SoundBeep(500, 250), SoundBeep(500, 50), SoundBeep(523, 1000))

; INSTRUCTIONS:
; - set SellingIsLive to false, until you're happy with how this works
; - set MoveGUIBox to false, until you've moved it to where you want it
; - go to the commodities market, sell screen, and find a high-value pixel on either side of the "SELL" tab (between "buy" and "compare")
;   use AHK's "window spy" if you've got really steady hands that's all you need,
;   or you can run this script and use ^!F10 (tells you what colors are in the pixels you picked) to nose around a bit
;   use those coordinates for SellTabX and SellTabY
; - select an item to sell, pick a pixel on the "SELL" button, use those coordinates for SellButtonX and SellButtonY
; - use ^!F10 while you go through the motions of selling stuff, it'll write the colors it sees under the X and Y coordinates
;   check that the colors I have here (Bright, Medium, Dim, White, Grey) are right for your screen/UI/etc
; - when you're ready to test, select your commodity so you're on the "SELL COMMODITY" screen where you select quantity
;   ^!F8 to start going through the motions of selling one at a time, but it'll RMouse to cancel rather than Space to sell
; - when you're ready to start selling, set SellingIsLive to true
; since it's reading the screen colors, if it loses sync it'll just stop rather than going crazy
; no need to tell it how many to sell, it'll empty your hold and stop
; if there's a lag spike or the server loses a key, it'll check it's in the right place and retry (up to 3 times)
;   (the "retries=" on the popup is the total number of retries since you hit ^!F8), "try=" is how many of the 3 retries you're on
; if you want an option to sell other size lots (like 2, or 8), down at the bottom edit the ^!F7 line

SellingIsLive := true						; set to false when you're getting set up, so we hit RMouse to cancel, rather than space to sell
MoveGUIBox := true							; set this to false until you've set its coordinates where you want it

SellTabX := 165								; texture means we gotta find the brightest pixel, look at 4 vertically stacked pixels for the brightest one
SellTabY := 368								;   to pick a good pixel, use AutoHotkey "window spy", and/or this script ^!F10
SellTabColorBright := 0xFE6F00				; focus is on tab
SellTabColorMedium := 0x4E2201				; active (vs buy) but focus is elsewhere
SellTabColorDim    := 0x1E0D00				; sell-item overlay dims the layer below

SellButtonX := 650							; button doesn't use textures so all the colors are the same
SellButtonY := 591							;   ideally pick a spot between the items on the list, to avoid an edge case when aborting with RButton
SellButtonColorBright := 0xFF6F00			; focus is on button, amount is >0
SellButtonColorDim    := 0x210E00			; focus is elsewhere, amount is >0
SellButtonColorWhite  := 0xC2C2C2			; focus is on button, amount is zero
SellButtonColorGrey   := 0x191919			; focus is elsewhere, amount is zero

EDWinWidth  := 0
EDWinHeight := 0
PauseOperation := false

G := Gui("AlwaysOnTop", "Sell1")
G.Add("Text", "X9", "SellTab")
G.Add("Text", "Y+5 Section", "X:")
G.Add("Text",, "Y:")
G.Add("Edit", "vSellTabX ys W60")
G.Add("UpDown", "vSellTabXUD Range1-20000", SellTabX)
G.Add("Edit", "vSellTabY W60")
G.Add("UpDown", "vSellTabYUD Range1-20000", SellTabY)
GuiCtrlSellTabColor := G.Add("Text", "Y+3 W80", "Color = ")

G.Add("Text", "X9 Y+8", "SellButton")
G.Add("Text", "Y+5 Section", "X:")
G.Add("Text",, "Y:")
G.Add("Edit", "vSellButtonX ys W60")
G.Add("UpDown", "vSellButtonXUD Range1-20000", SellButtonX)
G.Add("Edit", "vSellButtonY W60")
G.Add("UpDown", "vSellButtonYUD Range1-20000", SellButtonY)
GuiCtrlSellButtonColor := G.Add("Text", "Y+3 W80", "Color = ")

G.Add("Text", "X9 Y+8 Section", "Ctl-Alt-F9 to reload")
G.Add("Text", "Y+2", "Ctl-Alt-F10 to sample pixels")
G.Add("Text", "Y+2", "Ctl-Alt-F8 to sell 1 ton lots")
G.Add("Text", "Y+2", "Ctl-Alt-F7 to sell 2 ton lots")
G.Add("Text", "Y+2", "Pause to pause/go")
G.Add("Text", "Y+5 Section", "sold =")
GuiCtrlSold      := G.Add("Text", "X+3 ys", "0000")
GuiCtrlPaused    := G.Add("Text", "X+3 ys", "Starting up  ")
GuiCtrlWaitPre   := G.Add("Text", "X9 Y+5 Section", "Wait Prefix")
GuiCtrlWaitColor := G.Add("Text", "X+3 ys", "Wait Col")
GuiCtrlWaitSec   := G.Add("Text", "ys", "XX")
                    G.Add("Text", "X9 Y+5 Section", "try=")
GuiCtrlTry       := G.Add("Text", "X+0 ys", "000")
                    G.Add("Text", "X+5 ys", "retries=")
GuiCtrlRetries   := G.Add("Text", "X+0 ys", "0000")
G.Show()
if (MoveGUIBox) {
	; use WindowSpy to find the screen coordinates where you want the popup to display
	; look for "active window position:" and inside that, "screen coordinates"
	G.Move(3684,-172,,)
}

if (ED_HWND := WinExist("ahk_exe EliteDangerous64.exe")){
	WinActivate								; put ED on top, allegedly.  actually, the AHK popup is always on top.  so how do I get focus on the ED window?
	WinGetPos(,, &EDWinWidth, &EDWinHeight)
} else {
	exit
}

timekeeper(mode){							; total fluff, to satisfy curiosity.  nothing remotely critical, fiddle with to your heart's content
  static startTime := 0
  static pauseTime := 0
  if (mode = "pause") {
    pauseTime := A_TickCount
  } else if (mode = "resume") {
    startTime -= (pauseTime - A_TickCount)
  } else if (!mode){
	startTime := A_TickCount
  } else {
	elapsedTime := (A_TickCount - startTime) / mode
	if(elapsedTime>10000) {
	  msecs := Mod(elapsedTime, 1000)
	  t := DateAdd("20000101", elapsedTime//1000, "Seconds")
	  GuiCtrlPaused.Text := FormatTime(t, "mm:ss") "." Format("{1:04i}", msecs)
	} else {
	  GuiCtrlPaused.Text := Format("{1:.4f}", elapsedTime / 1000)
	}
  }
}

togglePause(){
  global PauseOperation
  PauseOperation := !PauseOperation
  PauseOperation ? (GuiCtrlPaused.Text := "Pausing") : ""
}

SamplePixels(){
    Saved := G.Submit(false)
	SellTabX := Saved.SellTabXUD
	SellTabY := Saved.SellTabYUD
	GuiCtrlSellTabColor.Text     := PixelGetColor(SellTabX, SellTabY)
	
	SellButtonX := Saved.SellButtonXUD
	SellButtonY := Saved.SellButtonYUD
	GuiCtrlSellButtonColor.Text  := PixelGetColor(SellButtonX, SellButtonY)
	return
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

; prefix, color string, seconds.  with the strings pre and col, we abuse the AHK language to form variable names
S1WaitForColor(pre, col, sec){
  GuiCtrlWaitPre.Text         := pre
  GuiCtrlWaitColor.Text       := col
  GuiCtrlWaitSec.Text         := sec
  result := WaitForColorPS(%pre%X, %pre%Y, %pre%Color%col%, sec * 1000)
  GuiCtrlSellTabColor.Text    := PixelGetColor(SellTabX, SellTabY)
  GuiCtrlSellButtonColor.Text := PixelGetColor(SellButtonX, SellButtonY)
  sleep 50
  return result
}

SendAndWaitForColor(msg, pre, col, sec, tries){
  thisTry := 0
  static retries := 0
  static oldPre := ""
  static oldCol := ""
  loop {
    GuiCtrlTry.Text := ++thisTry
	(thisTry>1) ? (GuiCtrlRetries.Text := ++retries) : ""
	if (msg)
	  SendEvent msg
	if (S1WaitForColor(pre, col, sec)) {
	  oldPre := pre
	  oldCol := col
      return true
	} 
	; if the old pixel test fails, we can't try again
	if(!msg || !oldPre || !oldCol || !S1WaitForColor(oldPre, oldCol, 0))
	  return false
  } until (thisTry >= tries)
  return false
}

VerifyStartingPosition(){
  MouseMove(EDWinWidth/2, EDWinHeight-30)								; put the mouse on the bottom of the ED window, but out of the way
  if (!SendAndWaitForColor("", "SellTab", "Dim", 1, 0))					; gotta start on the "SELL COMMODITY screen" selling your item
	return false
  SendEvent "ssaasw"													; get the focus onto the SELL button  
  return true
}

SmallSales(SellBy){
  sold := 0
  GuiCtrlRetries := 0
  global PauseOperation
  SetKeyDelay 125, 75
  if !VerifyStartingPosition()
    return beepExit
  sellCountStr := strRepeat("d", SellBy)
  sellKey := (SellingIsLive) ? "{Space}" : "{RButton}"							; false for testing, true for actually selling
  while true {
	timekeeper(sold)
	; TODO: check focus is on Elite Dangerous, otherwise break
	; to differentiate them for debugging, each prefix/color/seconds tuple should be unique.  it's displayed on the 2nd-from-bottom line in the popup
    if (S1WaitForColor("SellButton", "White", 0))						; nothing left, we're done!
	  return beepDone()
    if (!SendAndWaitForColor("", "SellButton", "Bright", 4, 0))
	  break
    if (!SendAndWaitForColor("{w down}", "SellButton", "Dim", 4, 3))	; cursor up, leave the key pressed  ; technique mentioned in power discord.  saves 0.46 seconds per sale at 720t, or 2m45s for a whole load
	  break
	if (!SendAndWaitForColor("{a down}", "SellButton", "Grey", 10, 3))	; cursor left, leave the key pressed, alllll the way to zero
	  break
	SendEvent("{a up}{w up}")											; release left & up.
	sleep 50									  						; gets its own sleep, because I was having trouble with the next key being seen
	if (!SendAndWaitForColor(sellCountStr, "SellButton", "Dim", 5, 3))	; cursor right for the number we want to sell; needs a different timeout from the previous SellButton/Dim
	  break
    if (!SendAndWaitForColor("s", "SellButton", "Bright", 5, 3))		; down to the sell button; needs a different timeout from the previous SellButton/Bright
	  break						
	GuiCtrlSold.Text := (sold += SellBy)
    if (!SendAndWaitForColor(sellKey, "SellTab", "Medium", 4, 3))		; 
	  break
	if (!SendAndWaitForColor("{Space}", "SellTab", "Dim", 4, 3))		; select the commodity from the list
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
  beepExit
}
; 4.3sec/sale at 720tons, 2.7sec/sale at 10tons

#HotIf WinActive("ahk_class FrontierDevelopmentsAppWinClass")
^!F10::SamplePixels
^!F9:: Send('{w up}{a up}{s up}{d up}{Space up}'), Reload(), SoundBeep(2000, 500)  ; Reload the script  [shamelessly stolen from OB]
^!F8::SmallSales(1)
^!F7::SmallSales(2)		; SmallSales will take any number you like, but keep it small or it'll be slow
Pause::togglePause		; make sure to be on the SELL COMMODITY screen when you un-pause
#HotIf
