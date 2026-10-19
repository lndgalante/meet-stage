import CoreGraphics
import Foundation

/// A point in a page as fractions (0...1) of its web area's width and height,
/// so it lands on the same spot whatever the page's zoom.
struct PagePoint: Sendable, Equatable {
    var x: Double
    var y: Double
}

extension PagePoint {
    /// `point` (global, top-left origin) within a web area's global frame.
    init(_ point: CGPoint, in webArea: CGRect) {
        x = webArea.width > 0 ? Double((point.x - webArea.minX) / webArea.width) : 0.5
        y = webArea.height > 0 ? Double((point.y - webArea.minY) / webArea.height) : 0.5
    }
}

/// One step a demo performs inside a browser tab. Each renders a fixed script;
/// callers, saved demos, and the model only ever supply its parameters, which
/// are encoded as JSON, never JavaScript.
enum BrowserPageOperation: Sendable, Equatable {
    /// Reports the control at a point without touching the page.
    case inspect(at: PagePoint)
    /// Pointer events and a click on the element at a point. With `expecting`,
    /// refuses unless the control there still has that label.
    case click(at: PagePoint, expecting: String? = nil)
    /// Replaces the text of the field at a point. Refuses password, payment,
    /// and one-time-code fields.
    case insertText(String, at: PagePoint)
    /// Return in the field at a point once its text starts with `expectedValue`,
    /// then the form's implicit submission, as a real Return would do.
    case submit(at: PagePoint, expectedValue: String)
    /// A key on the focused element, with Tab's focus move, Escape closing a
    /// modal dialog, and Page Up or Page Down scrolling.
    case key(DemoKey)
    /// Scrolls the content under a point by `points` (positive moves it up).
    /// `webAreaWidth` is the web area's width in points, to convert to CSS pixels.
    case scroll(at: PagePoint, points: Double, webAreaWidth: Double)

    /// Whether the step can change the page, so `commit` must run before it.
    var changesPage: Bool {
        if case .inspect = self { false } else { true }
    }

    /// The fixed script for this step, run only in a tab showing `page`.
    func script(on page: PageAddress) throws -> String {
        BrowserPageScripts.render(arguments: try BrowserPageScripts.encode(arguments(page: page)))
    }

    func arguments(page: PageAddress) -> BrowserPageScripts.Arguments {
        var arguments = BrowserPageScripts.Arguments(operation: "", page: page)
        switch self {
        case .inspect(let point):
            arguments.operation = "inspect"
            arguments.set(point)
        case .click(let point, let label):
            arguments.operation = "click"
            arguments.set(point)
            arguments.expect = label
        case .insertText(let text, let point):
            arguments.operation = "insertText"
            arguments.set(point)
            arguments.text = text
        case .submit(let point, let value):
            arguments.operation = "submit"
            arguments.set(point)
            arguments.expect = value
        case .key(let key):
            arguments.operation = "key"
            arguments.key = key.rawValue
        case .scroll(let point, let points, let width):
            arguments.operation = "scroll"
            arguments.set(point)
            arguments.points = points
            arguments.width = width
        }
        return arguments
    }
}

/// What a page script reports. Labels and values come from the page, so they
/// are untrusted data, like Accessibility labels.
struct BrowserPageResult: Decodable, Sendable, Equatable {
    enum Failure: String, Decodable, Sendable {
        /// The tab no longer shows the verified page; nothing happened.
        case tabMismatch
        case noElement, crossOriginFrame, noField, sensitiveField, disabled
        /// The control at the point no longer has the expected label.
        case targetChanged
        /// The field's text doesn't start with the text the step typed.
        case valueMismatch
        /// The field kept a value other than the typed text.
        case notAccepted
        case nothingToScroll
        /// The script threw; `acted` says whether it had touched the page.
        case exception
    }

    var ok: Bool
    var reason: Failure?
    /// The control's tag, role (ARIA or implicit), and label: its
    /// `aria-label`, labelling elements, button text, or visible text. Field
    /// values are never used as labels.
    var tag: String?
    var role: String?
    var label: String?
    /// A field's text after typing or submitting; never read from sensitive fields.
    var value: String?
    /// Distance scrolled: points for `scroll`, CSS pixels for Page Up and Page Down.
    var scrolled: Double?
    /// The script dispatched events or changed the page before it returned.
    var acted = false
    /// A password, payment, or one-time-code field.
    var sensitive = false
    /// The field at the point takes text (`inspect`).
    var editable = false
    /// Return submitted the field's form (`submit`).
    var submitted = false
    /// The exception's message, for diagnostics only.
    var detail: String?

    private enum CodingKeys: String, CodingKey {
        case ok, reason, tag, role, label, value, scrolled, acted, sensitive, editable, submitted, detail
    }

    init(ok: Bool, reason: Failure? = nil) {
        self.ok = ok
        self.reason = reason
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        // A reason missing from `Failure` still reads as a failure.
        reason = try container.decodeIfPresent(String.self, forKey: .reason).map { Failure(rawValue: $0) ?? .exception }
        tag = try container.decodeIfPresent(String.self, forKey: .tag)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        value = try container.decodeIfPresent(String.self, forKey: .value)
        scrolled = try container.decodeIfPresent(Double.self, forKey: .scrolled)
        acted = try container.decodeIfPresent(Bool.self, forKey: .acted) ?? false
        sensitive = try container.decodeIfPresent(Bool.self, forKey: .sensitive) ?? false
        editable = try container.decodeIfPresent(Bool.self, forKey: .editable) ?? false
        submitted = try container.decodeIfPresent(Bool.self, forKey: .submitted) ?? false
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
    }

    static func decode(_ text: String) -> BrowserPageResult? {
        try? JSONDecoder().decode(BrowserPageResult.self, from: Data(text.utf8))
    }
}

/// The one page script BetterMeets runs, as a fixed template. Its only input
/// is a JSON object of parameters, so quotes, backslashes, line breaks, and
/// emoji in typed text can never change what the script does.
enum BrowserPageScripts {
    struct Arguments: Codable, Equatable {
        var operation: String
        var page: PageAddress
        var x: Double?
        var y: Double?
        var text: String?
        var expect: String?
        var key: String?
        var points: Double?
        var width: Double?

        mutating func set(_ point: PagePoint) {
            x = point.x
            y = point.y
        }
    }

    /// Checks whether JavaScript from Apple Events is allowed; it evaluates to 2.
    static let probe = "1+1"

    /// The parameters as a JSON object literal, which is also valid JavaScript.
    static func encode(_ arguments: Arguments) throws -> String {
        var arguments = arguments
        arguments.x = arguments.x.map(clampFraction)
        arguments.y = arguments.y.map(clampFraction)
        if let width = arguments.width, !(width > 0) { throw BrowserScriptingError.failed("invalid web area width") }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Non-finite numbers throw here rather than reaching the page.
        guard let data = try? encoder.encode(arguments) else {
            throw BrowserScriptingError.failed("invalid page script parameters")
        }
        // JSON allows these two separators raw; older JavaScript engines don't.
        return String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    static func render(arguments json: String) -> String {
        prefix + json + body
    }

    private static func clampFraction(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : value
    }

    private static let prefix = "(function () {\n  \"use strict\";\n  const args = "

    // The page's main world runs this, so everything it reads from the page is untrusted.
    private static let body = #"""
        ;
          const state = { acted: false };
          const TEXT_TYPES = ["text", "search", "email", "url", "tel", "number", "password"];
          const BLOCKING_TYPES = ["text", "search", "url", "tel", "email", "password", "date", "month", "week", "time",
            "datetime-local", "number"];
          const SENSITIVE_AUTOCOMPLETE = ["cc-", "current-password", "new-password", "one-time-code"];
          const ACTIONABLE = "a[href],area[href],button,input,select,textarea,summary,label,[role=button],[role=link]," +
            "[role=menuitem],[role=menuitemcheckbox],[role=menuitemradio],[role=tab],[role=checkbox],[role=radio]," +
            "[role=switch],[role=option],[role=combobox],[role=textbox],[role=searchbox],[role=treeitem]," +
            "[contenteditable]:not([contenteditable=false])";
          const FOCUSABLE = "a[href],area[href],button,input,select,textarea,iframe,summary,[tabindex]," +
            "[contenteditable]:not([contenteditable=false])";
          const KEYS = {
            escape: { key: "Escape", code: "Escape", keyCode: 27 },
            tab: { key: "Tab", code: "Tab", keyCode: 9 },
            shift_tab: { key: "Tab", code: "Tab", keyCode: 9, shift: true },
            up: { key: "ArrowUp", code: "ArrowUp", keyCode: 38 },
            down: { key: "ArrowDown", code: "ArrowDown", keyCode: 40 },
            left: { key: "ArrowLeft", code: "ArrowLeft", keyCode: 37 },
            right: { key: "ArrowRight", code: "ArrowRight", keyCode: 39 },
            page_up: { key: "PageUp", code: "PageUp", keyCode: 33 },
            page_down: { key: "PageDown", code: "PageDown", keyCode: 34 },
            enter: { key: "Enter", code: "Enter", keyCode: 13 }
          };

          function clean(text) {
            return String(text == null ? "" : text).replace(/\s+/g, " ").trim().slice(0, 120);
          }

          function typeOf(node) {
            return String(node.type || "").toLowerCase();
          }

          // The parent in the composed tree, so lookups cross open shadow roots.
          function parentOf(node) {
            if (node.parentElement) return node.parentElement;
            const root = node.getRootNode ? node.getRootNode() : null;
            return root && root.host ? root.host : null;
          }

          function closest(node, test) {
            for (let current = node, depth = 0; current && depth < 256; current = parentOf(current), depth += 1) {
              if (current.nodeType === 1 && test(current)) return current;
            }
            return null;
          }

          function matches(node, selector) {
            try { return node.matches(selector); } catch (error) { return false; }
          }

          function isTextControl(node) {
            if (node.tagName === "TEXTAREA") return true;
            return node.tagName === "INPUT" && TEXT_TYPES.indexOf(typeOf(node)) >= 0;
          }

          function isSensitive(node) {
            if (node.tagName === "INPUT" && typeOf(node) === "password") return true;
            const autocomplete = String(node.getAttribute("autocomplete") || "").toLowerCase();
            return SENSITIVE_AUTOCOMPLETE.some((token) => autocomplete.indexOf(token) >= 0);
          }

          function isDisabled(node) {
            return node.disabled === true || matches(node, ":disabled");
          }

          function roleOf(node) {
            const explicit = clean(node.getAttribute("role")).split(" ")[0];
            if (explicit) return explicit.toLowerCase();
            const tag = node.tagName.toLowerCase();
            if (tag === "a" || tag === "area") return node.hasAttribute("href") ? "link" : "";
            if (tag === "button" || tag === "summary") return "button";
            if (tag === "select") return node.multiple || node.size > 1 ? "listbox" : "combobox";
            if (tag === "textarea") return "textbox";
            if (tag === "input") {
              const type = typeOf(node);
              if (["button", "submit", "reset", "image"].indexOf(type) >= 0) return "button";
              if (type === "checkbox" || type === "radio") return type;
              if (type === "range") return "slider";
              if (type === "search") return "searchbox";
              return TEXT_TYPES.indexOf(type) >= 0 ? "textbox" : type;
            }
            return node.isContentEditable === true ? "textbox" : "";
          }

          function labelOf(node) {
            const aria = clean(node.getAttribute("aria-label"));
            if (aria) return aria;
            const ids = clean(node.getAttribute("aria-labelledby"));
            if (ids) {
              const root = node.getRootNode();
              const text = clean(ids.split(" ").map((id) => {
                const label = root.getElementById ? root.getElementById(id) : null;
                return label ? label.textContent : "";
              }).join(" "));
              if (text) return text;
            }
            if (node.tagName === "INPUT" && ["button", "submit", "reset"].indexOf(typeOf(node)) >= 0) {
              return clean(node.value);
            }
            // A field's value is data, never its name.
            if (isTextControl(node) || node.tagName === "SELECT" || node.isContentEditable === true) {
              const labels = node.labels ? Array.from(node.labels).map((label) => label.innerText).join(" ") : "";
              return clean(labels) || clean(node.getAttribute("title")) || clean(node.getAttribute("placeholder"));
            }
            const image = node.querySelector ? node.querySelector("img[alt]") : null;
            return clean(node.innerText) || clean(node.getAttribute("title")) || clean(image ? image.alt : "");
          }

          function describe(node) {
            return { tag: node.tagName.toLowerCase(), role: roleOf(node), label: labelOf(node), sensitive: isSensitive(node) };
          }

          function decodePath(path) {
            let value = String(path || "");
            try { value = decodeURIComponent(value); } catch (error) {}
            return value || "/";
          }

          // The tab may have changed since BetterMeets checked it; act only on the verified page.
          function onExpectedPage(page) {
            if (!page) return false;
            const scheme = location.protocol.replace(/:$/, "").toLowerCase();
            const defaults = { http: 80, https: 443 };
            let port = location.port ? Number(location.port) : null;
            if (port === defaults[scheme]) port = null;
            const expectedPort = page.port == null ? null : page.port;
            return scheme === page.scheme && location.hostname.toLowerCase() === page.host && port === expectedPort &&
              decodePath(location.pathname) === page.path;
          }

          // The deepest element at a point, through open shadow roots and same-origin frames.
          function hitAt(fx, fy) {
            let view = window;
            let doc = document;
            let x = fx * view.innerWidth;
            let y = fy * view.innerHeight;
            let node = doc.elementFromPoint(x, y);
            for (let depth = 0; node && depth < 64; depth += 1) {
              if (node.shadowRoot) {
                const inner = node.shadowRoot.elementFromPoint(x, y);
                if (inner && inner !== node) {
                  node = inner;
                  continue;
                }
              }
              if (node.tagName !== "IFRAME" && node.tagName !== "FRAME") break;
              let inner = null;
              try { inner = node.contentDocument; } catch (error) { inner = null; }
              if (!inner || !inner.defaultView) return { crossOriginFrame: true };
              const box = node.getBoundingClientRect();
              const style = view.getComputedStyle(node);
              x -= box.left + node.clientLeft + (parseFloat(style.paddingLeft) || 0);
              y -= box.top + node.clientTop + (parseFloat(style.paddingTop) || 0);
              view = inner.defaultView;
              doc = inner;
              node = doc.elementFromPoint(x, y);
            }
            return node ? { node: node, view: view, x: x, y: y } : null;
          }

          // The focused element, through open shadow roots and same-origin frames.
          function deepActive() {
            let node = document.activeElement;
            for (let depth = 0; node && depth < 64; depth += 1) {
              if (node.shadowRoot && node.shadowRoot.activeElement) {
                node = node.shadowRoot.activeElement;
                continue;
              }
              if (node.tagName !== "IFRAME" && node.tagName !== "FRAME") break;
              let inner = null;
              try { inner = node.contentDocument; } catch (error) { inner = null; }
              if (!inner) return { crossOriginFrame: true };
              if (!inner.activeElement) break;
              node = inner.activeElement;
            }
            node = node || document.body;
            return node ? { node: node } : null;
          }

          function fire(target, Kind, type, init) {
            state.acted = true;
            return target.dispatchEvent(new Kind(type, init));
          }

          function mouseInit(hit, button, buttons, detail) {
            return { bubbles: true, cancelable: true, composed: true, view: hit.view, clientX: hit.x, clientY: hit.y,
              button: button, buttons: buttons, detail: detail };
          }

          function pointerInit(hit, button, buttons, detail) {
            return Object.assign(mouseInit(hit, button, buttons, detail), { pointerId: 1, pointerType: "mouse",
              isPrimary: true, width: 1, height: 1, pressure: buttons ? 0.5 : 0 });
          }

          // Like a real mouse-down: focus the nearest focusable ancestor, or leave the focused one.
          function focusForClick(node) {
            const doc = node.ownerDocument;
            const target = closest(node, (current) => matches(current, FOCUSABLE) && !isDisabled(current));
            if (target && typeof target.focus === "function") {
              target.focus({ preventScroll: true });
              return;
            }
            const active = doc.activeElement;
            if (active && active !== doc.body && typeof active.blur === "function") active.blur();
          }

          function inspect() {
            const hit = hitAt(args.x, args.y);
            if (!hit) return { ok: false, reason: "noElement" };
            if (hit.crossOriginFrame) return { ok: false, reason: "crossOriginFrame" };
            const field = fieldAt(hit.node);
            const control = field || closest(hit.node, (node) => matches(node, ACTIONABLE)) || hit.node;
            return Object.assign({ ok: true, editable: field != null }, describe(control));
          }

          function click() {
            const hit = hitAt(args.x, args.y);
            if (!hit) return { ok: false, reason: "noElement" };
            if (hit.crossOriginFrame) return { ok: false, reason: "crossOriginFrame" };
            const control = closest(hit.node, (node) => matches(node, ACTIONABLE)) || hit.node;
            const info = describe(control);
            if (info.sensitive) return Object.assign({ ok: false, reason: "sensitiveField" }, info);
            if (typeof args.expect === "string" && info.label !== args.expect) {
              return Object.assign({ ok: false, reason: "targetChanged" }, info);
            }
            if (isDisabled(control)) return Object.assign({ ok: false, reason: "disabled" }, info);
            const Pointer = hit.view.PointerEvent || hit.view.MouseEvent;
            const Mouse = hit.view.MouseEvent;
            const target = hit.node;
            fire(target, Pointer, "pointerover", pointerInit(hit, -1, 0, 0));
            fire(target, Mouse, "mouseover", mouseInit(hit, 0, 0, 0));
            const pointerDown = fire(target, Pointer, "pointerdown", pointerInit(hit, 0, 1, 0));
            // A cancelled pointerdown suppresses the compatibility mouse events, as in browsers.
            const mouseDown = pointerDown ? fire(target, Mouse, "mousedown", mouseInit(hit, 0, 1, 1)) : true;
            if (mouseDown) focusForClick(target);
            const again = target.isConnected ? null : hitAt(args.x, args.y);
            const released = again && again.node ? again.node : target;
            fire(released, Pointer, "pointerup", pointerInit(hit, 0, 0, 0));
            if (pointerDown) fire(released, Mouse, "mouseup", mouseInit(hit, 0, 0, 1));
            fire(released, Pointer, "click", pointerInit(hit, 0, 0, 1));
            return Object.assign({ ok: true }, info);
          }

          // The field a click at the point would type into.
          function fieldAt(node) {
            const control = closest(node, isTextControl);
            if (control) return control;
            const label = closest(node, (current) => current.tagName === "LABEL");
            if (label && label.control && isTextControl(label.control)) return label.control;
            const editable = closest(node, (current) => current.isContentEditable === true);
            if (!editable) return null;
            let host = editable;
            for (let parent = parentOf(host); parent && parent.isContentEditable === true; parent = parentOf(parent)) {
              host = parent;
            }
            return host;
          }

          function fieldOrRefusal() {
            const hit = hitAt(args.x, args.y);
            if (!hit) return { refusal: { ok: false, reason: "noElement" } };
            if (hit.crossOriginFrame) return { refusal: { ok: false, reason: "crossOriginFrame" } };
            const field = fieldAt(hit.node);
            if (!field) {
              const control = closest(hit.node, (node) => matches(node, ACTIONABLE)) || hit.node;
              return { refusal: Object.assign({ ok: false, reason: "noField" }, describe(control)) };
            }
            const info = describe(field);
            // Checked before anything reads the field.
            if (info.sensitive) return { refusal: Object.assign({ ok: false, reason: "sensitiveField" }, info) };
            if (isDisabled(field) || field.readOnly === true) {
              return { refusal: Object.assign({ ok: false, reason: "disabled" }, info) };
            }
            return { field: field, info: info };
          }

          function valueOf(field) {
            if (isTextControl(field)) return String(field.value);
            return String(field.innerText || "").replace(/\n$/, "");
          }

          function selectContents(field) {
            if (isTextControl(field)) {
              try { field.select(); } catch (error) {}
              return;
            }
            const doc = field.ownerDocument;
            const selection = doc.getSelection ? doc.getSelection() : null;
            if (!selection) return;
            const range = doc.createRange();
            range.selectNodeContents(field);
            selection.removeAllRanges();
            selection.addRange(range);
          }

          // The prototype's setter, so frameworks that track the value see the change.
          function setNativeValue(field, text) {
            const view = field.ownerDocument.defaultView || window;
            const prototype = field.tagName === "TEXTAREA" ? view.HTMLTextAreaElement.prototype :
              view.HTMLInputElement.prototype;
            const descriptor = Object.getOwnPropertyDescriptor(prototype, "value");
            if (!descriptor || !descriptor.set) return;
            descriptor.set.call(field, text);
            field.dispatchEvent(new view.InputEvent("input", { bubbles: true, composed: true, inputType: "insertText",
              data: text }));
            field.dispatchEvent(new view.Event("change", { bubbles: true }));
          }

          function insertText() {
            const found = fieldOrRefusal();
            if (found.refusal) return found.refusal;
            const field = found.field;
            const doc = field.ownerDocument;
            state.acted = true;
            field.focus({ preventScroll: true });
            selectContents(field);
            try {
              if (args.text === "") doc.execCommand("delete", false);
              else doc.execCommand("insertText", false, args.text);
            } catch (error) {}
            if (valueOf(field) !== args.text && isTextControl(field)) setNativeValue(field, args.text);
            const value = valueOf(field);
            const accepted = value === args.text || (args.text !== "" && value.indexOf(args.text) === 0);
            return Object.assign({ ok: accepted, value: value.slice(0, 4000) }, accepted ? {} : { reason: "notAccepted" },
              found.info);
          }

          function keyEvent(target, type, spec) {
            const view = target.ownerDocument.defaultView || window;
            const event = new view.KeyboardEvent(type, { key: spec.key, code: spec.code, bubbles: true, cancelable: true,
              composed: true, view: view, shiftKey: spec.shift === true });
            // KeyboardEventInit ignores the legacy codes that many pages still read.
            const charCode = type === "keypress" ? spec.keyCode : 0;
            Object.defineProperty(event, "keyCode", { get: () => spec.keyCode });
            Object.defineProperty(event, "which", { get: () => spec.keyCode });
            Object.defineProperty(event, "charCode", { get: () => charCode });
            state.acted = true;
            return target.dispatchEvent(event);
          }

          function isSubmitButton(node) {
            if (node.tagName === "BUTTON") return typeOf(node) === "submit";
            return node.tagName === "INPUT" && (typeOf(node) === "submit" || typeOf(node) === "image");
          }

          // HTML's implicit submission: the default button, or the form itself when no more
          // than one field blocks it.
          function submitImplicitly(form) {
            const elements = Array.from(form.elements);
            const button = elements.find(isSubmitButton);
            if (button) {
              if (isDisabled(button)) return null;
              button.click();
              return describe(button);
            }
            const blocking = elements.filter((node) => node.tagName === "INPUT" &&
              BLOCKING_TYPES.indexOf(typeOf(node)) >= 0);
            if (blocking.length > 1) return null;
            if (typeof form.requestSubmit === "function") {
              form.requestSubmit();
            } else {
              const view = form.ownerDocument.defaultView || window;
              if (form.dispatchEvent(new view.Event("submit", { bubbles: true, cancelable: true }))) form.submit();
            }
            return { tag: "form", role: "form", label: clean(form.getAttribute("aria-label")) };
          }

          function submit() {
            const found = fieldOrRefusal();
            if (found.refusal) return found.refusal;
            const field = found.field;
            if (valueOf(field).indexOf(args.expect) !== 0) {
              return Object.assign({ ok: false, reason: "valueMismatch" }, found.info);
            }
            const active = deepActive();
            if (!active || active.node !== field) field.focus({ preventScroll: true });
            const spec = KEYS.enter;
            const down = keyEvent(field, "keydown", spec);
            const pressed = down ? keyEvent(field, "keypress", spec) : false;
            let submitter = null;
            if (pressed && field.tagName === "INPUT" && field.form) submitter = submitImplicitly(field.form);
            keyEvent(field.isConnected ? field : field.ownerDocument.body, "keyup", spec);
            return Object.assign({ ok: true, value: valueOf(field).slice(0, 4000), submitted: submitter != null },
              submitter || found.info, { sensitive: false });
          }

          function canScroll(box) {
            if (box.scrollHeight <= box.clientHeight) return false;
            const view = box.ownerDocument.defaultView || window;
            const overflow = view.getComputedStyle(box).overflowY;
            return overflow === "auto" || overflow === "scroll" || overflow === "overlay";
          }

          // Scrollable ancestors, nearest first, then each document up through same-origin frames,
          // so scrolling chains outward like a real wheel.
          function scrollChain(node) {
            const chain = [];
            let current = node;
            for (let frames = 0; current && frames < 16; frames += 1) {
              const doc = current.ownerDocument;
              for (let box = current; box; box = parentOf(box)) {
                if (box.nodeType === 1 && box !== doc.scrollingElement && canScroll(box)) chain.push(box);
              }
              if (doc.scrollingElement) chain.push(doc.scrollingElement);
              let frame = null;
              try { frame = doc.defaultView ? doc.defaultView.frameElement : null; } catch (error) { frame = null; }
              current = frame;
            }
            return chain;
          }

          function scrollBox(box, pixels) {
            const before = box.scrollTop;
            try {
              box.scrollBy({ top: pixels, left: 0, behavior: "instant" });
            } catch (error) {
              box.scrollTop = before + pixels;
            }
            const moved = box.scrollTop - before;
            if (moved !== 0) state.acted = true;
            return moved;
          }

          function viewportHeight(box) {
            const doc = box.ownerDocument;
            return box === doc.scrollingElement && doc.defaultView ? doc.defaultView.innerHeight : box.clientHeight;
          }

          function scroll() {
            const hit = hitAt(args.x, args.y);
            if (!hit) return { ok: false, reason: "noElement" };
            if (hit.crossOriginFrame) return { ok: false, reason: "crossOriginFrame" };
            const pointsPerPixel = args.width / window.innerWidth;
            let moved = 0;
            for (const box of scrollChain(hit.node)) {
              moved = scrollBox(box, args.points / pointsPerPixel);
              if (moved !== 0) break;
            }
            if (moved === 0) return { ok: false, reason: "nothingToScroll", scrolled: 0 };
            return { ok: true, scrolled: moved * pointsPerPixel };
          }

          // Sequential focus: positive tabindex ascending, then document order; one radio per group.
          function isTabbable(node) {
            if (!matches(node, FOCUSABLE) || node.tabIndex < 0 || isDisabled(node)) return false;
            if (node.tagName === "INPUT" && typeOf(node) === "hidden") return false;
            if (node.closest && node.closest("[inert]")) return false;
            if (!node.getClientRects().length) return false;
            const view = node.ownerDocument.defaultView || window;
            if (view.getComputedStyle(node).visibility !== "visible") return false;
            if (node.tagName === "INPUT" && typeOf(node) === "radio" && node.name) {
              const scope = node.form || node.getRootNode();
              const group = Array.from(scope.querySelectorAll("input[type=radio]"))
                .filter((radio) => radio.name === node.name);
              const checked = group.find((radio) => radio.checked);
              return checked ? checked === node : group[0] === node;
            }
            return true;
          }

          function tabOrder(doc) {
            const found = [];
            const visit = (root) => {
              const walker = doc.createTreeWalker(root, 1);
              for (let node = walker.nextNode(); node; node = walker.nextNode()) {
                if (isTabbable(node)) found.push(node);
                if (node.shadowRoot) visit(node.shadowRoot);
              }
            };
            visit(doc.body || doc.documentElement);
            const positive = found.filter((node) => node.tabIndex > 0).sort((a, b) => a.tabIndex - b.tabIndex);
            return positive.concat(found.filter((node) => node.tabIndex === 0));
          }

          function moveFocus(from, backwards) {
            const order = tabOrder(from.ownerDocument);
            if (!order.length) return null;
            const index = order.indexOf(from);
            const next = index < 0 ? order[backwards ? order.length - 1 : 0] :
              order[(index + (backwards ? order.length - 1 : 1)) % order.length];
            next.focus();
            if (isTextControl(next)) {
              try { next.select(); } catch (error) {}
            }
            return next;
          }

          function closeModalDialog(doc) {
            let dialogs = [];
            try {
              dialogs = Array.from(doc.querySelectorAll("dialog[open]")).filter((dialog) => matches(dialog, ":modal"));
            } catch (error) {
              dialogs = [];
            }
            const dialog = dialogs[dialogs.length - 1];
            if (!dialog) return;
            const view = doc.defaultView || window;
            if (dialog.dispatchEvent(new view.Event("cancel", { cancelable: true }))) dialog.close();
          }

          function key() {
            const spec = KEYS[args.key];
            if (!spec) return { ok: false, reason: "exception", detail: "unknown key" };
            const active = deepActive();
            if (!active) return { ok: false, reason: "noElement" };
            if (active.crossOriginFrame) return { ok: false, reason: "crossOriginFrame" };
            const from = active.node;
            const proceed = keyEvent(from, "keydown", spec);
            let target = from;
            let scrolled = 0;
            if (proceed && spec.key === "Tab") {
              target = moveFocus(from, spec.shift === true) || from;
            } else if (proceed && spec.key === "Escape") {
              closeModalDialog(from.ownerDocument);
            } else if (proceed && (spec.key === "PageUp" || spec.key === "PageDown")) {
              const sign = spec.key === "PageDown" ? 1 : -1;
              for (const box of scrollChain(from)) {
                scrolled = scrollBox(box, sign * 0.875 * viewportHeight(box));
                if (scrolled !== 0) break;
              }
            }
            keyEvent(target.isConnected ? target : from.ownerDocument.body, "keyup", spec);
            return Object.assign({ ok: true, scrolled: scrolled }, describe(target));
          }

          const operations = { inspect: inspect, click: click, insertText: insertText, submit: submit, key: key,
            scroll: scroll };
          let result;
          try {
            result = onExpectedPage(args.page) ? operations[args.operation]() : { ok: false, reason: "tabMismatch" };
          } catch (error) {
            result = { ok: false, reason: "exception", detail: clean(error && error.message ? error.message : error) };
          }
          result.acted = state.acted;
          return JSON.stringify(result);
        })()
        """#
}
