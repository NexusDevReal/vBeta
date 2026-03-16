## TODO List
- [x] Phase 1: Architecture & Core Skeleton: Phase 1: Architecture & Core Skeleton
- Define the public API table (`Library`) with a clean, fluent interface (`Library:CreateWindow(...)`, `Library:Notify(...)`, etc.)
- Create internal module tables: `Theme`, `Animation`, `Utility`, `Components`, `Windows`, `Notifications`
- Write a single top-level comment block explaining loadstring usage, platform support, and high-level architecture
- Return the `Library` table at the very end of the script for loadstring compatibility


- [x] Phase 2: Theme System: Phase 2: Theme System
- Centralize all color constants in a `Theme` table (background, surface, accent, text, border, disabled)
- Provide a `Library:SetTheme(themeTable)` method that atomically updates every live element
- Auto-apply theme colors on instance creation via a `Theme.Apply(instance)` helper
- Ensure theme changes propagate to text, background, border stroke, and UICorner tinting


- [x] Phase 3: Utility & Layout Helpers: Phase 3: Utility & Layout Helpers
- Write helpers for automatic responsive padding, size constraints, and aspect-ratio preservation
- Create a `Create(class, props, children)` factory that auto-injects UICorner, UIStroke, UIPadding, UISizeConstraint, UIListLayout, or UIAspectRatioConstraint when props dictate
- Add a `SafeDestroy(instance)` function that disconnects all descendant connections and calls `instance:Destroy()`
- Provide a `GetViewportSize()` helper that returns usable screen size for anchoring and clamping


- [x] Phase 4: Animation Engine: Phase 4: Animation Engine
- Wrap `TweenService` in a non-blocking `Animation.Tween(instance, goal, info)` helper
- Predefine reusable `TweenInfo` presets: `Animation.Fast`, `Animation.Smooth`, `Animation.BackOut`
- Create `FadeIn`/`FadeOut` functions that tween GroupTransparency and CanvasGroup when available
- Guarantee all tweens auto-clean on instance destruction to prevent memory leaks


- [x] Phase 5: Window System: Phase 5: Window System
- Implement `Library:CreateWindow(title, defaultSize, defaultPosition)` returning a window object
- Window object API: `window:AddTab(label)`, `window:Remove()`, `window:SetVisible(bool)`, `window:SetTitle(text)`
- Auto-create title bar with draggable behavior using `UserInputService` and `GuiObject.InputBegan/Changed/Ended`
- Insert rounded container with UIStroke, UISizeConstraint, and UIPadding for consistent spacing
- Clamp window position within viewport on drag and resize


- [x] Phase 6: Tab System: Phase 6: Tab System
- `window:AddTab(label)` returns a tab object with `tab:AddButton(...)`, `tab:AddSlider(...)`, etc.
- Store tabs in a frame managed by `UIListLayout`; switch visibility via smooth fade animations
- Animate tab indicator sliding or underline using `Animation.Tween`
- Ensure only one tab body is visible at a time; hide others with `GroupTransparency = 1`


- [x] Phase 7: Component Library: Phase 7: Component Library
- **Button**: `tab:AddButton(text, callback)` with hover, press, disabled states and smooth scale/color tweens
- **Toggle (iOS Switch)**: `tab:AddToggle(text, default, callback)` with sliding thumb animation
- **Slider**: `tab:AddSlider(text, min, max, default, callback)` with draggable fill bar and value label
- **TextBox**: `tab:AddTextBox(text, default, callback)` with focus border color and placeholder text
- **Dropdown**: `tab:AddDropdown(text, list, default, callback)` with expanding list animated via `CanvasGroup`
- **Label**: `tab:AddLabel(text)` for read-only text with theming
- **Separator**: `tab:AddSeparator()` visual divider
- All components auto-inherit theme, support `:SetEnabled(bool)`, and clean connections on destruction


- [x] Phase 8: Notification System: Phase 8: Notification System
- `Library:Notify(text, duration)` queues notifications in a top-right screen stack
- Each notification frame uses `UICorner`, `UIStroke`, and `UIPadding`; insert into a `UIListLayout` container
- Animate slide-in from right and fade-out after `duration` (default 3 s)
- Cap max visible notifications (e.g., 4); queue excess and show as others dismiss
- Allow manual dismiss on tap/click with reverse animation


- [x] Phase 9: Mobile & Touch Optimization: Phase 9: Mobile & Touch Optimization
- Enforce minimum 44 × 44 px touch targets via `UISizeConstraint` on all interactive components
- Increase padding and font sizes when `UserInputService.TouchEnabled` and not `KeyboardEnabled`
- Disable hover effects on touch devices; instead, use brief press scale feedback
- Test drag thresholds to differentiate scroll from window drag


- [x] Phase 10: Final Integration & Delivery: Phase 10: Final Integration & Delivery
- Concatenate all modules into one standalone script file with clear section comments
- Verify single `return Library` at end for loadstring usage
- Ensure no `require`, no `ModuleScript`, and no external dependencies
- Deliver the complete `.lua` file to the user
