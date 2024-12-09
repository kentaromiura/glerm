import gleam/dynamic.{type Decoder, type Dynamic, DecodeError}
import gleam/erlang/atom
import gleam/erlang/process.{type Pid, type Selector, type Subject}
import gleam/function
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result

/// These represent the noted keys being held down when another action is taken,
/// like pressing another key or mouse button. For certain keys, things like
/// `Shift` will not be set, but instead return something like `A`.
pub type Modifier {
  Shift
  Alt
  Control
}

/// A particular keyboard key that was pressed. Either a character with its
/// value, or a special key. The `Unsupported` is for things like `PageUp`, etc
/// that I'm just not handling yet.
pub type KeyCode {
  Character(String)
  Enter
  Backspace
  Left
  Right
  Down
  Up
  Unsupported
}

/// Which mouse button was pressed. These are prefixed with `Mouse` in order to
/// avoid conflicting with the arrow keys defined in `KeyCode`.
pub type MouseButton {
  MouseLeft
  MouseRight
  MouseMiddle
}

/// The possible types of mouse events. I think most of these will also
/// have the mouse cursor position attached. That is not supported at the moment.
pub type MouseEvent {
  MouseDown(button: MouseButton, modifier: Option(Modifier))
  MouseUp(button: MouseButton, modifier: Option(Modifier))
  Drag(button: MouseButton, modifier: Option(Modifier))
  Moved
  ScrollDown
  ScrollUp
}

/// When the terminal window is focused or un-focused.
pub type FocusEvent {
  Lost
  Gained
}

/// The possible events coming back from the terminal. `Unknown` should
/// realistically never happen, since this library controls both ends of the
/// message passing.
pub type Event {
  Focus(event: FocusEvent)
  Key(key: KeyCode, modifier: Option(Modifier))
  Mouse(event: MouseEvent)
  Mouse2(event: MouseEvent, maybe_params: Option(Int))
  Resize(Int, Int)
  Unknown(tag: String, message: Dynamic)
}

fn decode_atom(val: String, actual: a) -> Decoder(a) {
  let real_atom = atom.create_from_string(val)
  let decode =
    function.compose(atom.from_dynamic, fn(maybe_atom) {
      maybe_atom
      |> result.then(fn(decoded) {
        case decoded == real_atom {
          True -> Ok(real_atom)
          False -> Error([DecodeError(val, atom.to_string(decoded), [])])
        }
      })
    })
  fn(msg) {
    decode(msg)
    |> result.replace(actual)
  }
}

fn modifier_decoder() -> Decoder(Option(Modifier)) {
  let decode_some = decode_atom("some", Some)
  dynamic.any([
    decode_atom("none", None),
    function.compose(
      dynamic.tuple2(decode_some, decode_atom("shift", Shift)),
      result.replace(_, Some(Shift)),
    ),
    function.compose(
      dynamic.tuple2(decode_some, decode_atom("alt", Alt)),
      result.replace(_, Some(Alt)),
    ),
    function.compose(
      dynamic.tuple2(decode_some, decode_atom("control", Control)),
      result.replace(_, Some(Control)),
    ),
  ])
}

fn keycode_decoder() -> Decoder(KeyCode) {
  dynamic.any([
    dynamic.tuple2(decode_atom("character", Character), dynamic.string)
      |> function.compose(fn(maybe_pair) {
        case maybe_pair {
          Ok(#(_character, value)) -> Ok(Character(value))
          Error(err) -> Error(err)
        }
      }),
    decode_atom("enter", Enter),
    decode_atom("backspace", Backspace),
    decode_atom("left", Left),
    decode_atom("right", Right),
    decode_atom("down", Down),
    decode_atom("up", Up),
    decode_atom("unsupported", Unsupported),
  ])
}

fn mouse_button_decoder() -> Decoder(MouseButton) {
  dynamic.any([
    decode_atom("mouse_left", MouseLeft),
    decode_atom("mouse_right", MouseRight),
    decode_atom("mouse_middle", MouseMiddle),
  ])
}

fn mouse_event_decoder() -> Decoder(MouseEvent) {
  dynamic.any([
    dynamic.tuple3(
      decode_atom("mouse_down", MouseDown),
      mouse_button_decoder(),
      modifier_decoder(),
    )
      |> function.compose(fn(maybe_triple) {
        case maybe_triple {
          Ok(#(_mouse_down, button, modifier)) ->
            Ok(MouseDown(button, modifier))
          Error(err) -> Error(err)
        }
      }),
    dynamic.tuple3(
      decode_atom("mouse_up", MouseUp),
      mouse_button_decoder(),
      modifier_decoder(),
    )
      |> function.compose(fn(maybe_triple) {
        case maybe_triple {
          Ok(#(_mouse_up, button, modifier)) -> Ok(MouseUp(button, modifier))
          Error(err) -> Error(err)
        }
      }),
    dynamic.tuple3(
      decode_atom("drag", Drag),
      mouse_button_decoder(),
      modifier_decoder(),
    )
      |> function.compose(fn(maybe_triple) {
        case maybe_triple {
          Ok(#(_drag, button, modifier)) -> Ok(Drag(button, modifier))
          Error(err) -> Error(err)
        }
      }),
    decode_atom("moved", Moved),
    dynamic.tuple2(decode_atom("scroll_down", ScrollDown), modifier_decoder())
      |> function.compose(fn(maybe_double) {
        case maybe_double {
          Ok(#(_mouse_down, _modifier)) -> Ok(ScrollDown)
          Error(err) -> Error(err)
        }
      }),
    decode_atom("scroll_down", ScrollDown),
    dynamic.tuple2(decode_atom("scroll_up", ScrollUp), modifier_decoder())
      |> function.compose(fn(maybe_double) {
        case maybe_double {
          Ok(#(_mouse_down, _modifier)) -> Ok(ScrollUp)
          Error(err) -> Error(err)
        }
      }),
    decode_atom("scroll_up", ScrollUp),
  ])
}

/// The events from the NIF are sent as messages to the calling process. These
/// do not go through a `process.Subject`, so they need to be explicitly
/// extracted from the mailbox. This selector will grab the given `Event`s for
/// each message that comes in.
pub fn selector() -> Selector(Event) {
  process.new_selector()
  |> process.selecting_record2(atom.create_from_string("focus"), fn(inner) {
    inner
    |> dynamic.any([decode_atom("gained", Gained), decode_atom("lost", Lost)])
    |> result.map(Focus)
    |> result.unwrap(Unknown("focus", inner))
  })
  |> process.selecting_record3(
    atom.create_from_string("key"),
    fn(first, second) {
      let key_code = keycode_decoder()(first)
      let modifier = modifier_decoder()(second)
      case key_code, modifier {
        Ok(code), Ok(mod) -> Key(code, mod)
        _, _ -> Unknown("key", dynamic.from([first, second]))
      }
    },
  )
  |> process.selecting_record2(atom.create_from_string("mouse"), fn(inner) {
    inner
    |> mouse_event_decoder()
    |> result.map(Mouse)
    |> result.lazy_unwrap(fn() { Unknown("mouse", inner) })
  })
  |> process.selecting_record3(
    atom.create_from_string("resize"),
    fn(first, second) {
      let columns = dynamic.int(first)
      let rows = dynamic.int(second)
      case columns, rows {
        Ok(col), Ok(rows) -> Resize(col, rows)
        _, _ -> Unknown("resize", dynamic.from([first, second]))
      }
    },
  )
}

/// Fully clears the terminal window
@external(erlang, "glerm_ffi", "clear")
pub fn clear() -> Nil

/// Write some string to the screen at the given #(column, row) coordinate
@external(erlang, "glerm_ffi", "draw")
pub fn draw(commands: List(#(Int, Int, String))) -> Result(Nil, Nil)

/// This is the "meat" of the library. This will fire up the NIF, which spawns
/// a thread to read for terminal events. The `Pid` provided here is where the
/// messages will be sent.
@external(erlang, "glerm_ffi", "listen")
fn listen(pid: Pid) -> Result(Nil, Nil)

/// Writes the given text wherever the cursor is
@external(erlang, "glerm_ffi", "print")
pub fn print(data: BitArray) -> Result(Nil, Nil)

/// Gives back the #(column, row) count of the current terminal. This can be
/// called to get the initial size, and then updated when `Resize` events
/// come in.
@external(erlang, "glerm_ffi", "size")
pub fn size() -> Result(#(Int, Int), Nil)

/// Moves the cursor to the given location
@external(erlang, "glerm_ffi", "move_to")
pub fn move_to(column: Int, row: Int) -> Nil

/// Enables "raw mode" for the terminal. This will do a better job than I can
/// at explaining what all that entails:
///
///   https://docs.rs/crossterm/latest/crossterm/terminal/index.html#raw-mode
///
/// If you want to control the entire screen, capture all input events, and
/// place the cursor anywhere, this is what you want.
@external(erlang, "glerm_ffi", "enable_raw_mode")
pub fn enable_raw_mode() -> Result(Nil, Nil)

/// Turns off raw mode. This will disable the features described in
/// `enable_raw_mode`.
@external(erlang, "glerm_ffi", "disable_raw_mode")
pub fn disable_raw_mode() -> Result(Nil, Nil)

/// This will create a new terminal "window" that you can interact with. This
/// will preserve the user's existing terminal when exiting the program, or
/// calling `leave_alternate_screen`.
@external(erlang, "glerm_ffi", "enter_alternate_screen")
pub fn enter_alternate_screen() -> Result(Nil, Nil)

/// See:  `enter_alternate_screen`
@external(erlang, "glerm_ffi", "leave_alternate_screen")
pub fn leave_alternate_screen() -> Result(Nil, Nil)

/// This enables the capturing of mouse events. Without this, those event types
/// will not be emitted by the NIF.
@external(erlang, "glerm_ffi", "enable_mouse_capture")
pub fn enable_mouse_capture() -> Result(Nil, Nil)

/// This will stop the capture of mouse events in the terminal.
@external(erlang, "glerm_ffi", "disable_mouse_capture")
pub fn disable_mouse_capture() -> Result(Nil, Nil)

@external(erlang, "glerm_ffi", "cursor_position")
pub fn cursor_position() -> Result(#(Int, Int), Nil)

@external(erlang, "glerm_ffi", "clear_current_line")
pub fn clear_current_line() -> Result(Nil, Nil)

@external(erlang, "glerm_ffi", "move_cursor_left")
pub fn move_cursor_left(count: Int) -> Result(Nil, Nil)

@external(erlang, "glerm_ffi", "move_cursor_right")
pub fn move_cursor_right(count: Int) -> Result(Nil, Nil)

@external(erlang, "glerm_ffi", "move_to_column")
pub fn move_to_column(column: Int) -> Result(Nil, Nil)

pub type ListenerMessage(user_message) {
  Term(Event)
  User(user_message)
}

pub type ListenerSubject(user_message) =
  Subject(ListenerMessage(user_message))

pub type EventSubject =
  Subject(Event)

pub type ListenerSpec(state, user_message) {
  ListenerSpec(
    init: fn() -> #(state, Option(Selector(user_message))),
    loop: fn(ListenerMessage(user_message), state) ->
      actor.Next(ListenerMessage(user_message), state),
  )
}

/// This will start the NIF listener and set up the `Event` selector. The spec
/// argument allows for behavior during the initialization of the actor. That
/// function returns the initial state, and an optional user selector. This
/// allows this actor to also receive any user-defined messages.
pub fn start_listener_spec(
  spec: ListenerSpec(state, user_message),
) -> Result(ListenerSubject(user_message), actor.StartError) {
  actor.start_spec(actor.Spec(
    init: fn() {
      let pid = process.self()
      let #(state, user_selector) = spec.init()
      let term_selector =
        selector()
        |> process.map_selector(Term)
      let selector =
        user_selector
        |> option.map(fn(user) {
          user
          |> process.map_selector(User)
          |> process.merge_selector(term_selector, _)
        })
        |> option.unwrap(term_selector)
      process.start(fn() { listen(pid) }, True)
      actor.Ready(state, selector)
    },
    init_timeout: 500,
    loop: spec.loop,
  ))
}

/// If you are not planning on sending custom messages to the terminal listener,
/// this method is the simplest. Give an initial state for the actor, and the
/// loop will receive only `Event`s and your provided state. To allow this
/// actor to receive additional user-defined messages, see `start_listener_spec`
pub fn start_listener(
  initial_state: state,
  loop: fn(Event, state) -> actor.Next(ListenerMessage(user_message), state),
) -> Result(EventSubject, actor.StartError) {
  actor.start_spec(
    actor.Spec(
      init: fn() {
        let pid = process.self()
        process.start(fn() { listen(pid) }, True)
        actor.Ready(initial_state, selector())
      },
      init_timeout: 500,
      loop: fn(msg, state) {
        case loop(msg, state) {
          actor.Continue(state, _selector) -> actor.continue(state)
          actor.Stop(reason) -> actor.Stop(reason)
        }
      },
    ),
  )
}
// TODO:
//  - test?
//  - docs
