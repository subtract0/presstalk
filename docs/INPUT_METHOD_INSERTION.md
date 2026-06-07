# Input Method Insertion Prototype

PressTalk's current production insertion path is:

1. direct Accessibility insertion when `AXIsProcessTrusted()` is true
2. pasteboard plus Cmd-V when Accessibility is trusted but direct AX insertion fails
3. temporary PressTalk input-method selection plus Darwin insert notification
   when Accessibility is not trusted
4. copy fallback when both Accessibility and input-method insertion are
   unavailable

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

Production PressTalk now uses this as the first fallback when Accessibility is
not trusted. It installs/registers the bundled input method if needed, briefly
selects it, posts the same Darwin notification, restores the previous input
source, and copies only if that setup fails.

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

Current builds sign the prototype with the same local development identity as
`PressTalk.app` unless `PRESSTALK_BUILD_STABLE_SIGNING=0` is set. The generated
bundle uses a no-mode source id, `com.am.presstalk.inputmethod.container`, and
carries the IMK metadata keys `CFBundleIconFile`, `LSBackgroundOnly`,
`LSUIElement`,
`InputMethodConnectionName`, `InputMethodServerControllerClass`,
`InputMethodServerDelegateClass`, `TISInputSourceID`,
`tsInputMethodIconFileKey`, and `tsInputMethodCharacterRepertoireKey`.

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

The bundled client probe performs the full reversible sequence without opening
System Settings: register, temporarily enable/select the PressTalk input method,
focus a local text view, post a payload, verify whether it lands, then restore
the original input source.

```bash
swift "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-input-method-client-probe.swift" --json
```

If `reason=input_method_not_selectable`, TIS did not expose the installed input
method as an enable/select-capable source. In that state, manual notification
probes are not meaningful yet because no focused client can be attached.

If `reason=input_method_select_failed` with `selectStatus=-50`, macOS recognized
the input method but refused to select it.

If `reason=input_method_enable_no_effect`, `enableStatus=0`, and
`enableNoEffect=true`, macOS recognized the input method and accepted the enable
API call, but the enabled-source requery still showed no PressTalk source. On
`mbp1`, this happened with the ad-hoc rc49 input-method bundle: the source was
visible as `com.am.presstalk.inputmethod.container` with
`TISTypeKeyboardInputMethodWithoutModes`, `enableCapable=true`, and
`selectCapable=true`, but `enabled=false` before and after enable, and direct
`TISSelectInputSource` returned `-50`. In that state production dictation will
fall back to copying unless Accessibility is trusted, the signing/trust state is
repaired, or the input method can be selected by macOS.

Current studio1 evidence after switching to the no-mode source shape:
`TISRegisterInputSource` returns `0`, the installed bundle verifies with
`Authority=PressTalk Local Development Code Signing`, LaunchServices can see the
app, and `PressTalkIMController` is exported under that Objective-C class name.
The status helper reports `recognizedSourceCount=1`,
`recognizedEnabledSourceCount=1`, source id
`com.am.presstalk.inputmethod.container`, type
`TISTypeKeyboardInputMethodWithoutModes`, and `selectCapable=true`.

The focused client probe now succeeds on `studio1` while
`AXIsProcessTrusted=false`: `success=true`, `reason=payload_inserted`,
`selectStatus=0`, `restoreStatus=0`, `observedText="PressTalk input method
client probe"`, and the input-method log records `client updated context=init`,
`controller initialized`, `insert requested`, and `insert notification handled
inserted=1`.

## Production Probe

The standalone client probe proves whether a selected PressTalk input method can
insert into its own focused helper window. The production insertion probe tests
the running PressTalk app process instead. It temporarily restarts PressTalk with
`PRESSTALK_ENABLE_PRODUCTION_INSERTION_PROBE=1`, opens a focused helper window,
posts a payload request to PressTalk, records whether the payload lands, and
then restores normal no-probe startup:

```bash
/bin/bash "$HOME/Applications/PressTalk.app/Contents/Resources/presstalk-run-production-insertion-probe.sh" --json
```

On `studio1`, this probe succeeds with `success=true`,
`targetCaptureSuccess=true`, and `traceProductionMethod=input_method_notification`.
On the current ad-hoc `mbp1` install, it fails with
`targetCaptureFailureHint=input_method_enable_no_effect` and trace evidence from
the running PressTalk app: `Input method insertion enable had no visible effect`,
`enabled_count=0`, and `Input method insertion unavailable
reason=enable_no_effect status=-50`. That confirms the blocker is not just the
standalone client probe context.

The non-IMK event route is also ruled out on `studio1` while
`AXIsProcessTrusted=false`. The bundled `presstalk-unicode-event-insert-probe`
now tries Unicode CGEvents through HID, session, annotated-session, and
PID-targeted posting. Local evidence from
`~/Library/Application Support/JarvisTap/Diagnostics/unicode-event-insert-probe-2026-06-06T21-54-53-225Z.json`
shows all four methods reported `postResult=posted` but `success=false` and
`observedText=""`.

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

The focused editable-field probe has succeeded on `studio1`, so production
dictation may use the same pending-insert file plus Darwin notification path
before falling back to copy when Accessibility is untrusted. It still needs
cross-machine smoke on `s1`, `s2`, and `mbp1` before the full app goal is proven.
