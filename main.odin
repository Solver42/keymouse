package main

import "core:c"
import "core:fmt"

// --- X11 C Bindings ---
Display :: rawptr
Window  :: c.ulong
Time    :: c.ulong
KeyCode :: c.uchar
KeySym  :: c.ulong
Bool    :: c.int

CurrentTime   :: 0
True          :: 1
False         :: 0
GrabModeAsync :: 1

ShiftMask :: 1 << 0
Mod1Mask  :: 1 << 3 // Alt

KeyPress   :: 2
KeyRelease :: 3

// Keysyms mapped to their hex values
XK_w: KeySym : 0x0077
XK_a: KeySym : 0x0061
XK_s: KeySym : 0x0073
XK_d: KeySym : 0x0064
XK_j: KeySym : 0x006a
XK_k: KeySym : 0x006b
XK_l: KeySym : 0x006c
XK_y: KeySym : 0x0079
XK_u: KeySym : 0x0075
XK_i: KeySym : 0x0069
XK_o: KeySym : 0x006f
XK_n: KeySym : 0x006e
XK_m: KeySym : 0x006d

XKeyEvent :: struct {
	type:        c.int,
	serial:      c.ulong,
	send_event:  Bool,
	display:     Display,
	window:      Window,
	root:        Window,
	subwindow:   Window,
	time:        Time,
	x, y:        c.int,
	x_root:      c.int,
	y_root:      c.int,
	state:       c.uint,
	keycode:     c.uint,
	same_screen: Bool,
}

XEvent :: struct #raw_union {
	type: c.int,
	xkey: XKeyEvent,
	pad:  [192]u8, // Padded to safely fit any XEvent size natively
}

when ODIN_OS == .Linux {
	foreign import xlib "system:X11"
	foreign import xtest "system:Xtst"

	@(default_calling_convention = "c")
	foreign xlib {
		XOpenDisplay               :: proc(display_name: cstring) -> Display ---
		XDefaultRootWindow         :: proc(display: Display) -> Window ---
		XkbSetDetectableAutoRepeat :: proc(display: Display, detectable: Bool, supported: ^Bool) -> Bool ---
		XKeysymToKeycode           :: proc(display: Display, keysym: KeySym) -> KeyCode ---
		XGrabKey                   :: proc(display: Display, keycode: c.int, modifiers: c.uint, grab_window: Window, owner_events: Bool, pointer_mode: c.int, keyboard_mode: c.int) -> c.int ---
		XNextEvent                 :: proc(display: Display, event: ^XEvent) -> c.int ---
		XFlush                     :: proc(display: Display) -> c.int ---
		XCloseDisplay              :: proc(display: Display) -> c.int ---
	}

@(default_calling_convention = "c")
	foreign xtest {
		XTestFakeRelativeMotionEvent :: proc(display: Display, dx, dy: c.int, delay: Time) -> c.int ---
		XTestFakeButtonEvent         :: proc(display: Display, button: c.uint, is_press: Bool, delay: Time) -> c.int ---
		XTestFakeKeyEvent            :: proc(display: Display, keycode: c.uint, is_press: Bool, delay: Time) -> c.int --- // Add this
	}
}

XK_Shift_L : KeySym : 0xFFE1
XK_Alt_L   : KeySym : 0xFFE9

// --- Main Application Logic ---
MOVE_STEP :: 20

main :: proc() {
	dpy := XOpenDisplay(nil)
	if dpy == nil {
		fmt.eprintln("Failed to open X display")
		return
	}
	defer XCloseDisplay(dpy)

	root := XDefaultRootWindow(dpy)

	// Prevent X11 from sending fake KeyRelease events when holding a key down for smooth dragging
	XkbSetDetectableAutoRepeat(dpy, True, nil)

	mod := c.uint(Mod1Mask | ShiftMask) // Alt + Shift

	keys := []KeySym{
		XK_w, XK_a, XK_s, XK_d, // Move
		XK_j, XK_k, XK_l,       // Clicks
		XK_y, XK_u, XK_i, XK_o, // Scroll
		XK_n, XK_m,             // Nav
	}

	keycodes := make([]KeyCode, len(keys))
	defer delete(keycodes)

	// Grab all target keys globally
	for key, i in keys {
		keycodes[i] = XKeysymToKeycode(dpy, key)
		XGrabKey(dpy, c.int(keycodes[i]), mod, root, True, GrabModeAsync, GrabModeAsync)
	}
    
	fmt.println("Keymouse started. Hold Alt+Shift to control the mouse...")

	ev: XEvent
	for {
		XNextEvent(dpy, &ev)

		if ev.type == KeyPress || ev.type == KeyRelease {
			code := ev.xkey.keycode
			is_press: Bool = ev.type == KeyPress ? True : False

		if is_press == True {
				switch code {
				// Movement
				case c.uint(keycodes[0]): XTestFakeRelativeMotionEvent(dpy, 0, -MOVE_STEP, CurrentTime) // w
				case c.uint(keycodes[1]): XTestFakeRelativeMotionEvent(dpy, -MOVE_STEP, 0, CurrentTime) // a
				case c.uint(keycodes[2]): XTestFakeRelativeMotionEvent(dpy, 0, MOVE_STEP, CurrentTime)  // s
				case c.uint(keycodes[3]): XTestFakeRelativeMotionEvent(dpy, MOVE_STEP, 0, CurrentTime)  // d

				// Clicks (Press down without Shift/Alt mask)
				case c.uint(keycodes[4]): button_event(dpy, 1, True, ev.xkey.state) // j (Left Click)
				case c.uint(keycodes[5]): button_event(dpy, 2, True, ev.xkey.state) // k (Middle Click)
				case c.uint(keycodes[6]): button_event(dpy, 3, True, ev.xkey.state) // l (Right Click)

				// Scrolling
				case c.uint(keycodes[7]):  click(dpy, 6, ev.xkey.state) // y
				case c.uint(keycodes[8]):  click(dpy, 5, ev.xkey.state) // u
				case c.uint(keycodes[9]):  click(dpy, 4, ev.xkey.state) // i
				case c.uint(keycodes[10]): click(dpy, 7, ev.xkey.state) // o

				// Navigation
				case c.uint(keycodes[11]): click(dpy, 8, ev.xkey.state) // n
				case c.uint(keycodes[12]): click(dpy, 9, ev.xkey.state) // m
				}
			} else {
				// Clicks (Release up without Shift/Alt mask)
				switch code {
				case c.uint(keycodes[4]): button_event(dpy, 1, False, ev.xkey.state) // j release
				case c.uint(keycodes[5]): button_event(dpy, 2, False, ev.xkey.state) // k release
				case c.uint(keycodes[6]): button_event(dpy, 3, False, ev.xkey.state) // l release
				}
			}
			XFlush(dpy)
		}
	}
}

// Unified helper to send mouse button events stripped of active modifier states
button_event :: proc(dpy: Display, button: c.uint, is_press: Bool, state: c.uint) {
	alt_code := c.uint(XKeysymToKeycode(dpy, XK_Alt_L))
	shift_code := c.uint(XKeysymToKeycode(dpy, XK_Shift_L))

	// 1. Temporarily release active modifiers logically
	if (state & ShiftMask) != 0 do XTestFakeKeyEvent(dpy, shift_code, False, CurrentTime)
	if (state & Mod1Mask) != 0  do XTestFakeKeyEvent(dpy, alt_code, False, CurrentTime)
	XFlush(dpy)

	// 2. Inject clean button event
	XTestFakeButtonEvent(dpy, button, is_press, CurrentTime)
	XFlush(dpy)

	// 3. Restore modifiers immediately
	if (state & Mod1Mask) != 0  do XTestFakeKeyEvent(dpy, alt_code, True, CurrentTime)
	if (state & ShiftMask) != 0 do XTestFakeKeyEvent(dpy, shift_code, True, CurrentTime)
	XFlush(dpy)
}

// Helper procedure for single-tap scroll and navigation actions
click :: proc(dpy: Display, button: c.uint, state: c.uint) {
	button_event(dpy, button, True, state)
	button_event(dpy, button, False, state)
}

