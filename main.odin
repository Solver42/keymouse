package main

import "core:c"
import "core:fmt"
import "core:time"

// Keyboard-as-mouse for X11.
// Hold Alt+Shift to enter mouse mode; it stays active until you release them.
//
//   WASD     move (fast by default)
//   H        even faster
//   P        slow
//   J/K/L    left / middle / right click (hold to drag)
//   I/U      scroll up / down
//   Y/O      scroll left / right
//   N/M      back / forward
//
// Build: odin build keymouse.odin -file -out:keymouse
// Run:   ./keymouse

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
GrabSuccess   :: 0

ShiftMask :: 1 << 0
LockMask  :: 1 << 1
Mod1Mask  :: 1 << 3 // Alt
Mod2Mask  :: 1 << 4 // NumLock

XK_Shift_L : KeySym : 0xFFE1
XK_Shift_R : KeySym : 0xFFE2
XK_Alt_L   : KeySym : 0xFFE9
XK_Alt_R   : KeySym : 0xFFEA
XK_w : KeySym : 0x0077
XK_a : KeySym : 0x0061
XK_s : KeySym : 0x0073
XK_d : KeySym : 0x0064
XK_h : KeySym : 0x0068
XK_p : KeySym : 0x0070
XK_j : KeySym : 0x006a
XK_k : KeySym : 0x006b
XK_l : KeySym : 0x006c
XK_y : KeySym : 0x0079
XK_u : KeySym : 0x0075
XK_i : KeySym : 0x0069
XK_o : KeySym : 0x006f
XK_n : KeySym : 0x006e
XK_m : KeySym : 0x006d

XKeyEvent :: struct {
	type:           c.int,
	serial:         c.ulong,
	send_event:     Bool,
	display:        Display,
	window:         Window,
	root:           Window,
	subwindow:      Window,
	time:           Time,
	x, y:           c.int,
	x_root, y_root: c.int,
	state:          c.uint,
	keycode:        c.uint,
	same_screen:    Bool,
}

XEvent :: struct #raw_union {
	type: c.int,
	xkey: XKeyEvent,
	pad:  [192]u8,
}

when ODIN_OS == .Linux {
	foreign import xlib "system:X11"
	foreign import xtest "system:Xtst"

	@(default_calling_convention = "c")
	foreign xlib {
		XOpenDisplay       :: proc(display_name: cstring) -> Display ---
		XDefaultRootWindow :: proc(display: Display) -> Window ---
		XKeysymToKeycode   :: proc(display: Display, keysym: KeySym) -> KeyCode ---
		XGrabKey           :: proc(display: Display, keycode: c.int, modifiers: c.uint, grab_window: Window, owner_events: Bool, pointer_mode: c.int, keyboard_mode: c.int) -> c.int ---
		XGrabKeyboard      :: proc(display: Display, grab_window: Window, owner_events: Bool, pointer_mode: c.int, keyboard_mode: c.int, time: Time) -> c.int ---
		XUngrabKeyboard    :: proc(display: Display, time: Time) -> c.int ---
		XPending           :: proc(display: Display) -> c.int ---
		XNextEvent         :: proc(display: Display, event: ^XEvent) -> c.int ---
		XQueryKeymap       :: proc(display: Display, keys_return: ^[32]u8) -> c.int ---
		XFlush             :: proc(display: Display) -> c.int ---
		XSync              :: proc(display: Display, discard: Bool) -> c.int ---
		XCloseDisplay      :: proc(display: Display) -> c.int ---
	}

	@(default_calling_convention = "c")
	foreign xtest {
		XTestFakeRelativeMotionEvent :: proc(display: Display, dx, dy: c.int, delay: Time) -> c.int ---
		XTestFakeButtonEvent         :: proc(display: Display, button: c.uint, is_press: Bool, delay: Time) -> c.int ---
		XTestFakeKeyEvent            :: proc(display: Display, keycode: c.uint, is_press: Bool, delay: Time) -> c.int ---
		XTestGrabControl             :: proc(display: Display, impervious: Bool) -> c.int ---
	}
}

MOVE_SPEED_SLOW   :: 3
MOVE_SPEED_FAST   :: 16
MOVE_SPEED_FASTER :: 48
SCROLL_FRAMES     :: 4

is_physically_down :: proc(keys: ^[32]u8, kc: KeyCode) -> bool {
	if kc == 0 do return false
	return (keys[kc / 8] & (1 << (kc % 8))) != 0
}

fake_key :: proc(dpy: Display, kc: KeyCode, press: bool) {
	if kc == 0 do return
	XTestFakeKeyEvent(dpy, c.uint(kc), Bool(press), CurrentTime)
}

grab_key_all_locks :: proc(dpy: Display, kc: KeyCode, base: c.uint, root: Window) {
	if kc == 0 do return
	locks := []c.uint{0, Mod2Mask, LockMask, Mod2Mask | LockMask}
	for extra in locks {
		XGrabKey(dpy, c.int(kc), base | extra, root, True, GrabModeAsync, GrabModeAsync)
	}
}

any_button_held :: proc(btn_held: ^[4]bool) -> bool {
	return btn_held[1] || btn_held[2] || btn_held[3]
}

main :: proc() {
	dpy := XOpenDisplay(nil)
	if dpy == nil {
		fmt.eprintln("Failed to open X display")
		return
	}
	defer XCloseDisplay(dpy)

	root := XDefaultRootWindow(dpy)
	XTestGrabControl(dpy, True)

	kc_alt_l   := XKeysymToKeycode(dpy, XK_Alt_L)
	kc_alt_r   := XKeysymToKeycode(dpy, XK_Alt_R)
	kc_shift_l := XKeysymToKeycode(dpy, XK_Shift_L)
	kc_shift_r := XKeysymToKeycode(dpy, XK_Shift_R)

	kc_w := XKeysymToKeycode(dpy, XK_w)
	kc_a := XKeysymToKeycode(dpy, XK_a)
	kc_s := XKeysymToKeycode(dpy, XK_s)
	kc_d := XKeysymToKeycode(dpy, XK_d)
	kc_h := XKeysymToKeycode(dpy, XK_h)
	kc_p := XKeysymToKeycode(dpy, XK_p)
	kc_j := XKeysymToKeycode(dpy, XK_j)
	kc_k := XKeysymToKeycode(dpy, XK_k)
	kc_l := XKeysymToKeycode(dpy, XK_l)
	kc_y := XKeysymToKeycode(dpy, XK_y)
	kc_u := XKeysymToKeycode(dpy, XK_u)
	kc_i := XKeysymToKeycode(dpy, XK_i)
	kc_o := XKeysymToKeycode(dpy, XK_o)
	kc_n := XKeysymToKeycode(dpy, XK_n)
	kc_m := XKeysymToKeycode(dpy, XK_m)

	action_keys := []KeyCode{
		kc_w, kc_a, kc_s, kc_d, kc_h, kc_p,
		kc_j, kc_k, kc_l,
		kc_y, kc_u, kc_i, kc_o,
		kc_n, kc_m,
	}

	// Swallow action keys while Alt+Shift is held (all NumLock/CapsLock variants).
	for kc in action_keys {
		grab_key_all_locks(dpy, kc, Mod1Mask | ShiftMask, root)
	}
	// Wake mouse mode as soon as Alt+Shift itself is held.
	grab_key_all_locks(dpy, kc_shift_l, Mod1Mask, root)
	grab_key_all_locks(dpy, kc_shift_r, Mod1Mask, root)
	grab_key_all_locks(dpy, kc_alt_l, ShiftMask, root)
	grab_key_all_locks(dpy, kc_alt_r, ShiftMask, root)

	btn_held: [4]bool
	scroll_cooldown: [6]int
	kb_grabbed := false

	// XTestFakeKeyEvent of Alt/Shift updates the server keymap, so while a
	// button is down we remember the physical modifiers we temporarily released
	// and treat mouse mode as still active until we restore them.
	mods_stripped := false
	had_alt_l, had_alt_r, had_shift_l, had_shift_r: bool

	strip_mods :: proc(
		dpy: Display,
		keys: ^[32]u8,
		kc_alt_l, kc_alt_r, kc_shift_l, kc_shift_r: KeyCode,
		mods_stripped: ^bool,
		had_alt_l, had_alt_r, had_shift_l, had_shift_r: ^bool,
	) {
		if mods_stripped^ do return
		had_alt_l^ = is_physically_down(keys, kc_alt_l)
		had_alt_r^ = is_physically_down(keys, kc_alt_r)
		had_shift_l^ = is_physically_down(keys, kc_shift_l)
		had_shift_r^ = is_physically_down(keys, kc_shift_r)
		if had_alt_l^ do fake_key(dpy, kc_alt_l, false)
		if had_alt_r^ do fake_key(dpy, kc_alt_r, false)
		if had_shift_l^ do fake_key(dpy, kc_shift_l, false)
		if had_shift_r^ do fake_key(dpy, kc_shift_r, false)
		mods_stripped^ = true
		XSync(dpy, False)
	}

	restore_mods :: proc(
		dpy: Display,
		kc_alt_l, kc_alt_r, kc_shift_l, kc_shift_r: KeyCode,
		mods_stripped: ^bool,
		had_alt_l, had_alt_r, had_shift_l, had_shift_r: bool,
		btn_held: ^[4]bool,
	) {
		if !mods_stripped^ do return
		if any_button_held(btn_held) do return
		if had_alt_l do fake_key(dpy, kc_alt_l, true)
		if had_alt_r do fake_key(dpy, kc_alt_r, true)
		if had_shift_l do fake_key(dpy, kc_shift_l, true)
		if had_shift_r do fake_key(dpy, kc_shift_r, true)
		mods_stripped^ = false
		XSync(dpy, False)
	}

	sync_button :: proc(
		dpy: Display,
		pressed: bool,
		btn: c.uint,
		held: ^bool,
		keys: ^[32]u8,
		kc_alt_l, kc_alt_r, kc_shift_l, kc_shift_r: KeyCode,
		mods_stripped: ^bool,
		had_alt_l, had_alt_r, had_shift_l, had_shift_r: ^bool,
		btn_held: ^[4]bool,
	) {
		if pressed && !held^ {
			strip_mods(
				dpy, keys,
				kc_alt_l, kc_alt_r, kc_shift_l, kc_shift_r,
				mods_stripped, had_alt_l, had_alt_r, had_shift_l, had_shift_r,
			)
			XTestFakeButtonEvent(dpy, btn, True, CurrentTime)
			held^ = true
		} else if !pressed && held^ {
			XTestFakeButtonEvent(dpy, btn, False, CurrentTime)
			held^ = false
			restore_mods(
				dpy, kc_alt_l, kc_alt_r, kc_shift_l, kc_shift_r,
				mods_stripped, had_alt_l^, had_alt_r^, had_shift_l^, had_shift_r^,
				btn_held,
			)
		}
	}

	pulse_scroll :: proc(
		dpy: Display,
		btn: c.uint,
		key_pressed: bool,
		cooldown: ^int,
		keys: ^[32]u8,
		kc_alt_l, kc_alt_r, kc_shift_l, kc_shift_r: KeyCode,
		mods_stripped: ^bool,
		had_alt_l, had_alt_r, had_shift_l, had_shift_r: ^bool,
		btn_held: ^[4]bool,
	) {
		if key_pressed {
			if cooldown^ <= 0 {
				// Shift+wheel is treated as horizontal scroll by GTK/Qt/Firefox.
				// Drop Alt+Shift for the pulse, then put them back.
				was_stripped := mods_stripped^
				if !was_stripped {
					strip_mods(
						dpy, keys,
						kc_alt_l, kc_alt_r, kc_shift_l, kc_shift_r,
						mods_stripped, had_alt_l, had_alt_r, had_shift_l, had_shift_r,
					)
				}
				XTestFakeButtonEvent(dpy, btn, True, CurrentTime)
				XTestFakeButtonEvent(dpy, btn, False, CurrentTime)
				if !was_stripped {
					restore_mods(
						dpy, kc_alt_l, kc_alt_r, kc_shift_l, kc_shift_r,
						mods_stripped, had_alt_l^, had_alt_r^, had_shift_l^, had_shift_r^,
						btn_held,
					)
				}
				cooldown^ = SCROLL_FRAMES
			} else {
				cooldown^ -= 1
			}
		} else {
			cooldown^ = 0
		}
	}

	release_all_buttons :: proc(dpy: Display, btn_held: ^[4]bool) {
		for btn in 1 ..= 3 {
			if btn_held[btn] {
				XTestFakeButtonEvent(dpy, c.uint(btn), False, CurrentTime)
				btn_held[btn] = false
			}
		}
	}

	for {
		keys: [32]u8
		XQueryKeymap(dpy, &keys)

		alt := is_physically_down(&keys, kc_alt_l) || is_physically_down(&keys, kc_alt_r)
		shift := is_physically_down(&keys, kc_shift_l) || is_physically_down(&keys, kc_shift_r)
		// After strip_mods the server thinks Alt/Shift are up. Stay in mouse mode
		// until we restore them, otherwise WASD dies mid-drag.
		in_mode := mods_stripped || any_button_held(&btn_held) || (alt && shift)

		if !in_mode {
			if kb_grabbed {
				release_all_buttons(dpy, &btn_held)
				restore_mods(
					dpy, kc_alt_l, kc_alt_r, kc_shift_l, kc_shift_r,
					&mods_stripped, had_alt_l, had_alt_r, had_shift_l, had_shift_r,
					&btn_held,
				)
				XUngrabKeyboard(dpy, CurrentTime)
				kb_grabbed = false
				XFlush(dpy)
			}
			// Sleep until the next Alt+Shift grab event.
			ev: XEvent
			XNextEvent(dpy, &ev)
			continue
		}

		if !kb_grabbed {
			if XGrabKeyboard(dpy, root, False, GrabModeAsync, GrabModeAsync, CurrentTime) == GrabSuccess {
				kb_grabbed = true
			}
		}

		// Drop grab-queue events so they cannot be mistaken for real releases.
		for XPending(dpy) > 0 {
			ev: XEvent
			XNextEvent(dpy, &ev)
		}

		// Re-read after draining. Keymap is the source of truth for WASD/clicks,
		// not KeyPress/KeyRelease (those fire extra releases when strip_mods
		// changes the modifier state).
		XQueryKeymap(dpy, &keys)

		dx, dy: c.int = 0, 0
		w_down := is_physically_down(&keys, kc_w)
		a_down := is_physically_down(&keys, kc_a)
		s_down := is_physically_down(&keys, kc_s)
		d_down := is_physically_down(&keys, kc_d)
		speed: c.int = MOVE_SPEED_FAST
		if is_physically_down(&keys, kc_p) {
			speed = MOVE_SPEED_SLOW
		} else if is_physically_down(&keys, kc_h) {
			speed = MOVE_SPEED_FASTER
		}
		if w_down do dy -= speed
		if s_down do dy += speed
		if a_down do dx -= speed
		if d_down do dx += speed
		if dx != 0 || dy != 0 {
			XTestFakeRelativeMotionEvent(dpy, dx, dy, CurrentTime)
		}

		sync_button(
			dpy, is_physically_down(&keys, kc_j), 1, &btn_held[1], &keys,
			kc_alt_l, kc_alt_r, kc_shift_l, kc_shift_r,
			&mods_stripped, &had_alt_l, &had_alt_r, &had_shift_l, &had_shift_r, &btn_held,
		)
		sync_button(
			dpy, is_physically_down(&keys, kc_k), 2, &btn_held[2], &keys,
			kc_alt_l, kc_alt_r, kc_shift_l, kc_shift_r,
			&mods_stripped, &had_alt_l, &had_alt_r, &had_shift_l, &had_shift_r, &btn_held,
		)
		sync_button(
			dpy, is_physically_down(&keys, kc_l), 3, &btn_held[3], &keys,
			kc_alt_l, kc_alt_r, kc_shift_l, kc_shift_r,
			&mods_stripped, &had_alt_l, &had_alt_r, &had_shift_l, &had_shift_r, &btn_held,
		)

		pulse_scroll(dpy, 4, is_physically_down(&keys, kc_i), &scroll_cooldown[0], &keys,
			kc_alt_l, kc_alt_r, kc_shift_l, kc_shift_r,
			&mods_stripped, &had_alt_l, &had_alt_r, &had_shift_l, &had_shift_r, &btn_held)
		pulse_scroll(dpy, 5, is_physically_down(&keys, kc_u), &scroll_cooldown[1], &keys,
			kc_alt_l, kc_alt_r, kc_shift_l, kc_shift_r,
			&mods_stripped, &had_alt_l, &had_alt_r, &had_shift_l, &had_shift_r, &btn_held)
		pulse_scroll(dpy, 6, is_physically_down(&keys, kc_y), &scroll_cooldown[2], &keys,
			kc_alt_l, kc_alt_r, kc_shift_l, kc_shift_r,
			&mods_stripped, &had_alt_l, &had_alt_r, &had_shift_l, &had_shift_r, &btn_held)
		pulse_scroll(dpy, 7, is_physically_down(&keys, kc_o), &scroll_cooldown[3], &keys,
			kc_alt_l, kc_alt_r, kc_shift_l, kc_shift_r,
			&mods_stripped, &had_alt_l, &had_alt_r, &had_shift_l, &had_shift_r, &btn_held)
		pulse_scroll(dpy, 8, is_physically_down(&keys, kc_n), &scroll_cooldown[4], &keys,
			kc_alt_l, kc_alt_r, kc_shift_l, kc_shift_r,
			&mods_stripped, &had_alt_l, &had_alt_r, &had_shift_l, &had_shift_r, &btn_held)
		pulse_scroll(dpy, 9, is_physically_down(&keys, kc_m), &scroll_cooldown[5], &keys,
			kc_alt_l, kc_alt_r, kc_shift_l, kc_shift_r,
			&mods_stripped, &had_alt_l, &had_alt_r, &had_shift_l, &had_shift_r, &btn_held)

		XFlush(dpy)
		time.sleep(16 * time.Millisecond)
	}
}
