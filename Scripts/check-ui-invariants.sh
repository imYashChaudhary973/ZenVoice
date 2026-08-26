#!/bin/zsh
# Structural invariants for the settings window.
#
# These encode decisions that are invisible to the compiler and easy to undo by
# accident — every one of them was a real defect at some point:
#
#   * a screen shown as a tab rendering its own page scaffold, so the section
#     grew a second title, a second rule, and a nested scroll view;
#   * the sidebar width hand-copied into the title bar and drifting apart;
#   * the cloud preview window activating the app and stealing focus from the
#     application the transcript was about to be inserted into.
set -u

project_dir=${0:A:h:h}
screens="$project_dir/Sources/ZenVoice/Screens"
failures=0

pass() { echo "PASS  $1" }
fail() { echo "FAIL  $1" >&2; failures=$((failures + 1)) }

# 1. Screens rendered as tabs must not carry their own ZenScreen scaffold.
tab_children=(
    ShortcutsScreen AudioScreen OverlayScreen
    LanguagesScreen ModelsScreen
    CommandModeScreen CommandsScreen WriteModeScreen FormattingScreen
    VoiceProfileScreen AppProfilesScreen
    HistoryScreen AudioHistoryScreen LecturesScreen InsightsScreen
    HelpScreen UpdatesScreen
)
for screen in $tab_children; do
    if grep -q "ZenScreen(" "$screens/$screen.swift"; then
        fail "$screen renders its own ZenScreen; its container owns the scaffold"
    else
        pass "$screen supplies content only"
    fi
done

# 2. Each top-level destination owns one scaffold. Related views may use the
#    native segmented strip inside that destination instead of filling the
#    sidebar with one row per subview.
containers=(
    DictationScreen PersonalScreen HistoryContainerScreen
    HelpAndAboutScreen
)
for screen in $containers; do
    count=$(grep -c "ZenScreen(" "$screens/$screen.swift")
    if [[ "$count" != "1" ]]; then
        fail "$screen has $count ZenScreen scaffolds, expected exactly 1"
    else
        pass "$screen owns one titled scaffold"
    fi
done

# 3. The sidebar width is a token, not a literal repeated in the title bar.
settings_view="$project_dir/Sources/ZenVoice/ZenVoiceSettingsView.swift"
if ! grep -q "ideal: ZenDesign.Layout.sidebarWidth" "$settings_view"; then
    fail "ZenVoiceSettingsView does not use the shared sidebar-width token"
else
    pass "sidebar width comes from ZenDesign.Layout"
fi

if grep -qE '\"Configure\"|\"Library\"|case languagesAndModels' "$settings_view"; then
    fail "sidebar restores category headings or a combined language/model route"
else
    pass "sidebar exposes flat destinations without subheadings"
fi

# 3b. The main shell must use native macOS navigation and toolbar chrome.
if ! grep -q "NavigationSplitView" "$settings_view"; then
    fail "settings shell does not use NavigationSplitView"
elif grep -q "ZenToolbarCluster" "$settings_view"; then
    fail "settings shell paints a custom toolbar instead of using window toolbar items"
else
    pass "settings shell uses native split navigation and toolbar chrome"
fi

chrome="$project_dir/Sources/ZenVoice/ZenChrome.swift"
if ! grep -q "accessibilityReduceTransparency" "$chrome"; then
    fail "sidebar material has no Reduce Transparency fallback"
else
    pass "sidebar material honors Reduce Transparency"
fi

if ! grep -q "glassEffect" "$chrome" \
    || ! grep -q "#available(macOS 26" "$chrome"; then
    fail "floating chrome has no versioned Liquid Glass implementation"
else
    pass "floating chrome uses Liquid Glass with an availability fallback"
fi

if grep -q "minWidth: 1_200" "$settings_view"; then
    fail "settings window still requires a 1200-point display"
else
    pass "settings window supports compact widths"
fi

model_manager="$project_dir/Sources/ZenVoice/ModelManagerViewModel.swift"
overview="$project_dir/Sources/ZenVoice/Screens/OverviewScreen.swift"
if ! grep -q "selectEngine(EngineIdentifiers.whisper)" "$model_manager"; then
    fail "choosing a Whisper model does not select the Whisper engine"
elif ! grep -q "activeEngineDisplayName" "$overview"; then
    fail "Overview reports a stored model instead of the resolved engine"
else
    pass "model selection and displayed engine share one source of truth"
fi

components="$project_dir/Sources/ZenVoice/ZenV2Components.swift"
if ! grep -q "struct ZenTabStrip" "$components" \
    || ! grep -q "matchedGeometryEffect" "$components"; then
    fail "subsection navigation does not use the shared sliding toggle"
else
    pass "subsection navigation uses the shared sliding toggle"
fi

if grep -q "contentMaxWidth" "$components"; then
    fail "settings pages still cap content instead of filling the window"
else
    pass "settings pages fill the available window width"
fi

overlay_kind="$project_dir/Sources/ZenVoice/Overlay/OverlayKind.swift"
overlay_panel="$project_dir/Sources/ZenVoice/Overlay/OverlayPanelController.swift"
if ! grep -q "size(fitting" "$overlay_kind" \
    || ! grep -q "kind.size(fitting" "$overlay_panel"; then
    fail "dictation overlays do not adapt to the active display"
else
    pass "dictation overlays adapt to compact and full-screen displays"
fi

if ! grep -q "fullScreenAuxiliary" "$overlay_panel" \
    || grep -q "stationary" "$overlay_panel"; then
    fail "dictation overlays cannot appear over fullscreen apps"
else
    pass "dictation overlays join fullscreen Spaces"
fi

shortcuts="$screens/ShortcutsScreen.swift"
if ! grep -q "shortcutControls" "$shortcuts" \
    || ! grep -q "keyboard.badge.ellipsis" "$shortcuts"; then
    fail "dictation hotkeys do not share aligned controls and hold-key icon"
else
    pass "dictation hotkeys share aligned controls and hold-key icon"
fi

languages="$screens/LanguagesScreen.swift"
cloud_config="$screens/CloudAIConfigurationView.swift"
if ! grep -q "ZenMenuPicker" "$languages" \
    || ! grep -q "ZenMenuPicker" "$cloud_config"; then
    fail "language or provider selectors bypass the shared menu control"
else
    pass "language and provider selectors use the shared menu control"
fi

if ! grep -q "struct ZenKeycap" "$components" \
    || ! grep -q "ZenKeycap(" "$settings_view"; then
    fail "painted buttons no longer use the shared Opensource UI keycap"
else
    pass "painted buttons use the shared 3D keycap"
fi

if ! grep -q "struct ZenHoldToDeleteButton" "$components" \
    || ! grep -q "ZenHoldToDeleteButton" "$screens/PrivacyScreen.swift" \
    || ! grep -q "Copy transcript" "$screens/HistoryScreen.swift" \
    || ! grep -q "ZenKebabMenu" "$screens/HistoryScreen.swift"; then
    fail "History/Privacy no longer use the shared copy, kebab, or hold-delete controls"
else
    pass "History uses copy and kebab; Privacy uses hold-to-delete"
fi

lectures="$screens/LecturesScreen.swift"
if ! grep -q "ZenSecondaryButtonStyle" "$lectures" \
    || ! grep -q "frame(minHeight: 44)" "$lectures" \
    || ! grep -q "ZenHoldToDeleteButton" "$lectures" \
    || ! grep -q "accessibilityReduceMotion" "$settings_view" \
    || ! grep -q "accessibilityReduceMotion" "$components"; then
    fail "lecture controls lost 44pt targets or shared Reduce Motion handling"
else
    pass "lecture controls keep 44pt targets and shared Reduce Motion handling"
fi

if ! grep -q "wrappedModelID" "$screens/ModelsScreen.swift" \
    || ! grep -q "only loads" "$screens/ModelsScreen.swift" \
    || ! grep -q 'Text("Models")' "$screens/ModelsScreen.swift" \
    || ! grep -q "ZenSystemAlert" "$screens/ModelsScreen.swift" \
    || ! grep -q "ModelMismatchToastOverlay" "$screens/ModelsScreen.swift"; then
    fail "Models screen no longer lists engine-linked files or mismatch alerts"
else
    pass "Models screen lists engine files and blocks mismatches"
fi

# 4. The cloud preview must never activate the app.
#    Comment lines are stripped first: the file explains *why* it does not call
#    NSApp.activate, and matching that prose failed the check the prose exists
#    to document.
preview="$project_dir/Sources/ZenVoice/CloudAIPreviewWindowController.swift"
if grep -v '^\s*//' "$preview" | grep -q "NSApp.activate"; then
    fail "the cloud preview activates ZenVoice and will steal focus from the target app"
else
    pass "the cloud preview does not steal focus"
fi
if ! grep -q "nonactivatingPanel" "$preview"; then
    fail "the cloud preview is not a non-activating panel"
else
    pass "the cloud preview is a non-activating panel"
fi

# 5. Cloud enhancement must be able to apply without prompting.
if ! grep -q "autoApply" "$project_dir/Sources/ZenVoiceCore/CloudAIEnhancement.swift"; then
    fail "CloudAIConfiguration has no autoApply preference"
else
    pass "cloud enhancement can apply without re-asking"
fi

# 6. Permission state must distinguish "not asked" from "denied".
settings_vm="$project_dir/Sources/ZenVoice/SettingsViewModel.swift"
if ! grep -q "case notRequested" "$settings_vm" || ! grep -q "case denied" "$settings_vm"; then
    fail "PermissionStatus collapses 'not asked yet' and 'denied' into one state"
else
    pass "permission states are distinguished"
fi
if ! grep -q "beginWatchingPermissions" "$settings_vm"; then
    fail "permissions are sampled once instead of watched"
else
    pass "permissions are watched for out-of-process changes"
fi

# Permission polling runs once a second while the settings window is visible.
# Model discovery performs a full SHA-256 verification, so calling it here
# blocks the main actor for longer than the timer interval on large models.
if grep -q "ZenVoiceConfiguration\.discover" "$settings_vm"; then
    fail "permission status polling performs full model discovery"
else
    pass "permission polling performs no model verification"
fi

# 6b. Rows whose controls cannot shrink must be able to wrap.
#
#     Button labels are `lineLimit(1)` and `fixedSize`, so they never wrap or
#     truncate — which means a row of them has a hard minimum width. SwiftUI
#     resolves an over-constrained row by *overflowing*, not by clipping, so
#     such a row silently pushes its card wider than the column and draws over
#     whatever sits beside it. At the 940pt minimum window the Home action row
#     did exactly that, spilling across the Recent activity card. Every row
#     that mixes fixed-width controls has to offer a stacked alternative.
fixed_rows=(
    "Screens/OverviewScreen.swift:quickActionsPanel"
    "Screens/VoiceProfileScreen.swift:correctionEntryFields"
)
for entry in $fixed_rows; do
    file="$project_dir/Sources/ZenVoice/${entry%%:*}"
    label="${entry##*:}"
    if ! grep -q "ViewThatFits" "$file"; then
        fail "${entry%%:*} has an unshrinkable control row ($label) with no ViewThatFits fallback"
    else
        pass "${entry%%:*} wraps its fixed-width control rows"
    fi
done

# 6c. The Home two-column grid must collapse rather than overflow.
overview="$project_dir/Sources/ZenVoice/Screens/OverviewScreen.swift"
if grep -q "minWidth: 300, maxWidth: .infinity" "$overview"; then
    fail "OverviewScreen pins a minimum column width; a minimum is a request, not a constraint — use ViewThatFits"
else
    pass "OverviewScreen sizes its columns by what fits"
fi

# 7. No UI type below the 11pt supporting-text floor. The share card is an
#    exported image with its own canvas scale, not window chrome.
offenders=$(grep -rn "size: 9[,.)]\|size: 10[,.)]\|size: 10\.5" \
    "$project_dir/Sources/ZenVoice" --include="*.swift" \
    | grep -v "ShareHighlightCard.swift" || true)
if [[ -n "$offenders" ]]; then
    fail "type below the 11pt floor:\n$offenders"
else
    pass "no UI type below the 11pt floor"
fi

if (( failures > 0 )); then
    echo "\n$failures UI invariant(s) failed." >&2
    exit 1
fi
echo "\nAll UI invariants hold."
