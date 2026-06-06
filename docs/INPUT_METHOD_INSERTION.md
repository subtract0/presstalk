# Input Method Insertion Prototype

PressTalk's current production insertion path is:

1. direct Accessibility insertion when `AXIsProcessTrusted()` is true
2. pasteboard plus Cmd-V when Accessibility is trusted but direct AX insertion fails
3. copy fallback when Accessibility is not trusted

The automated paste self-test has already shown that synthetic Cmd-V events do
not reliably land in a focused text field without Accessibility trust. Keep that
result as the reason not to keep iterating on CGEvent paste variants.

## Candidate Architecture

The remaining non-Accessibility path is an input method. Apple's
InputMethodKit is built for communication between input methods and client
applications. It creates an `IMKInputController` per client input session, and
the client conforms to `IMKTextInput`, which exposes
`insertText(_:replacementRange:)`.

The prototype in `Sources/PressTalkInputMethod` starts an `IMKServer`, tracks the
current `IMKTextInput` client, and listens for the Darwin notification
`com.am.presstalk.inputmethod.insert`. On notification it reads:

```text
~/Library/Application Support/JarvisTap/input-method-insert.txt
```

and asks the active input client to insert that text at the current insertion
point.

This is intentionally not wired into production PressTalk yet. The goal is to
prove whether an installed and selected PressTalk input method can insert into a
focused client on Apple Silicon without Accessibility trust.

## Build

Build the app bundle without installing it:

```bash
bash scripts/build_presstalk_input_method.sh
```

Install it into the user input-method folder:

```bash
bash scripts/build_presstalk_input_method.sh --install
```

The installed bundle path is:

```text
~/Library/Input Methods/PressTalkInputMethod.app
```

Installing the bundle does not select it as the active input source. macOS may
require logout/login or manual input-source selection before the input method
receives a text client.

## Status

Check whether macOS recognizes the input method without changing anything:

```bash
swift "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-input-method-status.swift"
```

Register the installed input method bundle without selecting it:

```bash
swift "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-input-method-status.swift" --register
```

Enable the input source only when you are ready to make it selectable:

```bash
swift "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-input-method-status.swift" --enable
```

Select the input source only when you are ready to run an insertion probe:

```bash
swift "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-input-method-status.swift" --select
```

`--enable` changes the enabled input-source list, and `--select` changes the
current input source. Run the read-only command first and record the current
source so you can restore your normal keyboard/input method after the probe.

## Probe

After the input method is installed, selected, and focused in an editable text
field, post a probe insert:

```bash
bash scripts/presstalk_input_method_insert_probe.sh "PressTalk input method probe"
```

Then inspect:

```bash
tail -n 40 ~/Library/Logs/presstalk_input_method.log
```

Success requires both:

- the log reports `insert requested`
- the probe text appears in the focused text field

If the log reports `no_current_client`, the input method app did not have an
active text input client. If the log reports `insert requested` but no text
appears, the client accepted the request path but insertion is still not proven.

## Promotion Rule

Do not wire this into production dictation until the probe succeeds in a focused
editable field on at least one target Mac. After that, PressTalk can write the
final transcript to the pending insert file and post the same Darwin
notification instead of copy fallback when Accessibility is untrusted.
