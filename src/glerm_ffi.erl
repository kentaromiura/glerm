-module(glerm_ffi).

-export([listen/1, print/1, size/0, clear/0, move_to/2, draw/1, enable_raw_mode/0,
         disable_raw_mode/0, enter_alternate_screen/0, leave_alternate_screen/0,
         enable_mouse_capture/0, disable_mouse_capture/0, cursor_position/0, clear_current_line/0,
         move_cursor_right/1, move_cursor_left/1, move_to_column/1]).

-nifs([{listen, 1},
       {print, 1},
       {size, 0},
       {clear, 0},
       {clear_current_line, 0},
       {move_to, 2},
       {draw, 1},
       {enable_raw_mode, 0},
       {disable_raw_mode, 0},
       {enter_alternate_screen, 0},
       {leave_alternate_screen, 0},
       {enable_mouse_capture, 0},
       {disable_mouse_capture, 0},
       {cursor_position, 0},
       {move_cursor_left, 1},
       {move_cursor_right, 1},
       {move_to_column, 1}]).

-on_load init/0.

init() ->
  Arch = erlang:system_info(system_architecture),
  Priv = code:priv_dir(glerm),
  ArchPath =
    case Arch of
      "x86_64-pc-linux" ++ _ ->
        filename:join(Priv, "linux");
      "win32" ->
        filename:join(Priv, "windows");
      "x86_64-apple-darwin" ++ _ ->
        filename:join(Priv, "macos");
      "aarch64-apple-darwin" ++ _ ->
        filename:join(Priv, "macos-arm")
    end,
  Path = filename:join(ArchPath, libglerm),
  erlang:load_nif(Path, 0).

listen(_Pid) ->
  exit(nif_library_not_loaded).

print(_Data) ->
  exit(nif_library_not_loaded).

size() ->
  exit(nif_library_not_loaded).

clear() ->
  exit(nif_library_not_loaded).

clear_current_line() ->
  exit(nif_library_not_loaded).

move_to(_Column, _Row) ->
  exit(nif_library_not_loaded).

draw(_Commands) ->
  exit(nif_library_not_loaded).

enable_raw_mode() ->
  exit(nif_library_not_loaded).

disable_raw_mode() ->
  exit(nif_library_not_loaded).

cursor_position() ->
  exit(nif_library_not_loaded).

enter_alternate_screen() ->
  exit(nif_library_not_loaded).

leave_alternate_screen() ->
  exit(nif_library_not_loaded).

enable_mouse_capture() ->
  exit(nif_library_not_loaded).

disable_mouse_capture() ->
  exit(nif_library_not_loaded).

move_cursor_left(_Count) ->
  exit(nif_library_not_loaded).

move_cursor_right(_Count) ->
  exit(nif_library_not_loaded).

move_to_column(_Column) ->
  exit(nif_library_not_loaded).
