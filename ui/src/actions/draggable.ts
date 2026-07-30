import { SendNUI } from "@utils/SendNUI";

interface DragOptions {
  /** Which stored position this panel writes back to. */
  panel: "radar" | "plate";
  /** Dragging is only possible while the control panel holds NUI focus. */
  enabled: boolean;
}

/**
 * Mouse-driven repositioning.
 *
 * Deliberately not the HTML5 drag-and-drop API: CEF does not fire dragstart
 * reliably inside a FiveM NUI, which is the same reason the patrol board in
 * ps-mdt moves its cards with plain mouse events.
 *
 * Position is written back as a fraction of the viewport rather than in
 * pixels, so a panel parked against an edge stays there when the operator
 * changes resolution.
 */
/**
 * The panel's size as it appears on screen.
 *
 * The CSS scale sits on an inner element, not on the draggable node itself —
 * the node carries the enter/leave transition, and both write to `transform`,
 * so they cannot share an element. That means measuring the node is wrong
 * twice over: `offsetHeight` ignores transforms entirely, and even its
 * `getBoundingClientRect` excludes a scaled child that overflows it.
 *
 * An element's own rect *does* reflect its own transform, so the scaled child
 * is the thing to measure.
 */
function visualRect(node: HTMLElement): DOMRect {
  const scaled = node.firstElementChild as HTMLElement | null;
  return (scaled ?? node).getBoundingClientRect();
}

export function draggable(node: HTMLElement, options: DragOptions) {
  let opts = options;
  let dragging = false;
  let offsetX = 0;
  let offsetY = 0;

  const onMouseMove = (e: MouseEvent) => {
    if (!dragging) return;

    // Re-measured on every move rather than cached at mousedown: the panel's
    // height depends on settings the operator can change while it is open
    // (plate rows on or off, interface scale), and a stale measurement is the
    // same bug in slower motion.
    const rect = visualRect(node);
    const maxX = Math.max(0, window.innerWidth - rect.width);
    const maxY = Math.max(0, window.innerHeight - rect.height);
    const x = Math.min(Math.max(0, e.clientX - offsetX), maxX);
    const y = Math.min(Math.max(0, e.clientY - offsetY), maxY);

    node.style.left = x + "px";
    node.style.top = y + "px";
  };

  const onMouseUp = () => {
    if (!dragging) return;
    dragging = false;

    window.removeEventListener("mousemove", onMouseMove);
    window.removeEventListener("mouseup", onMouseUp);

    // Saved from the node, not the scaled child: the stored fraction is the
    // anchor's position, and the scale grows from that corner outwards.
    const rect = node.getBoundingClientRect();
    SendNUI("savePosition", {
      panel: opts.panel,
      x: rect.left / window.innerWidth,
      y: rect.top / window.innerHeight,
    });
  };

  const onMouseDown = (e: MouseEvent) => {
    if (!opts.enabled || e.button !== 0) return;

    // A press on a control inside the panel is aimed at that control, not at
    // the panel. Without this the power button and the mode switches each
    // start a drag as well as firing, and the panel creeps across the screen
    // every time the operator touches one.
    const target = e.target as HTMLElement | null;
    if (target && target.closest("button, input, select, textarea, a")) return;

    e.preventDefault();

    const rect = node.getBoundingClientRect();
    offsetX = e.clientX - rect.left;
    offsetY = e.clientY - rect.top;
    dragging = true;

    window.addEventListener("mousemove", onMouseMove);
    window.addEventListener("mouseup", onMouseUp);
  };

  node.addEventListener("mousedown", onMouseDown);

  // A position stored before the plate rows were merged in was saved for a
  // shorter panel, and the same fraction now puts the bottom of it off screen.
  // Nudge it back once, after layout has settled, and persist the correction so
  // it does not have to happen again.
  const settle = requestAnimationFrame(() => {
    const rect = visualRect(node);
    const maxX = Math.max(0, window.innerWidth - rect.width);
    const maxY = Math.max(0, window.innerHeight - rect.height);

    if (rect.left <= maxX && rect.top <= maxY && rect.left >= 0 && rect.top >= 0) return;

    const x = Math.min(Math.max(0, rect.left), maxX);
    const y = Math.min(Math.max(0, rect.top), maxY);
    node.style.left = x + "px";
    node.style.top = y + "px";

    SendNUI("savePosition", {
      panel: opts.panel,
      x: x / window.innerWidth,
      y: y / window.innerHeight,
    });
  });

  return {
    update(next: DragOptions) {
      opts = next;
    },
    destroy() {
      cancelAnimationFrame(settle);
      node.removeEventListener("mousedown", onMouseDown);
      window.removeEventListener("mousemove", onMouseMove);
      window.removeEventListener("mouseup", onMouseUp);
    },
  };
}
