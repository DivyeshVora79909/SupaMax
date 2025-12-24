export function Card(props) {
  return (
    <div
      class={`bg-white border border-slate-200 rounded-xl shadow-sm ${
        props.class || ""
      }`}
    >
      {props.children}
    </div>
  );
}
