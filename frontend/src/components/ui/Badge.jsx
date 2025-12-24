export function Badge(props) {
  const variants = {
    default: "bg-slate-100 text-slate-700",
    success: "bg-emerald-50 text-emerald-700 border-emerald-200",
    warning: "bg-amber-50 text-amber-700 border-amber-200",
    blue: "bg-blue-50 text-blue-700 border-blue-200",
    purple: "bg-indigo-50 text-indigo-700 border-indigo-200",
    red: "bg-red-50 text-red-700 border-red-200",
  };

  return (
    <span
      class={`px-2.5 py-0.5 rounded-full text-xs font-medium border ${
        variants[props.variant || "default"]
      } ${props.class || ""}`}
    >
      {props.children}
    </span>
  );
}
