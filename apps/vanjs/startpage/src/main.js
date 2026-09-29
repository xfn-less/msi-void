import van from "vanjs-core";

const { button, form, h1, input, main, p, section, time, ul, li } = van.tags;

const clock = van.state(new Date());

setInterval(() => {
  clock.val = new Date();
}, 1000);

const searchBilibili = (keyword) => {
  const q = keyword.trim();
  if (!q) return;
  location.href = `https://search.bilibili.com/all?keyword=${encodeURIComponent(q)}`;
};

const App = () => {
  const query = van.state("");

  return main(
    { class: "page" },
    section(
      { class: "hero" },
      h1("bili"),
      time(() =>
        clock.val.toLocaleString(undefined, {
          weekday: "short",
          hour: "2-digit",
          minute: "2-digit",
        }),
      ),
      p("本地入口 · 搜索后进入官网"),
    ),
    form(
      {
        class: "search",
        onsubmit: (e) => {
          e.preventDefault();
          searchBilibili(query.val);
        },
      },
      input({
        type: "search",
        name: "q",
        placeholder: "搜索视频、UP 主…",
        autocomplete: "off",
        autofocus: true,
        value: query,
        oninput: (e) => (query.val = e.target.value),
      }),
      button({ type: "submit" }, "搜索"),
    ),
    TodoList(), // 添加 TodoList 组件
  );
};

const TodoList = () => {
  const todos = van.state([]);
  const newTodo = van.state("");

  const addTodo = () => {
    const text = newTodo.val.trim();
    if (!text) return;
    todos.val = [...todos.val, text];
    newTodo.val = "";
  };

  const removeTodo = (index) => {
    todos.val = todos.val.filter((_, i) => i !== index);
  };

  return section(
    { class: "todo-list" },
    form(
      {
        class: "todo-add",
        onsubmit: (e) => {
          e.preventDefault();
          addTodo();
        },
      },
      input({
        type: "text",
        placeholder: "添加任务",
        value: newTodo,
        oninput: (e) => (newTodo.val = e.target.value),
      }),
      button({ type: "submit" }, "添加"),
    ),
    // VanJS: children must be a function to re-render when state changes
    ul(() =>
      todos.val.map((todo, index) =>
        li(
          todo,
          " ",
          button({ type: "button", onclick: () => removeTodo(index) }, "删除"),
        ),
      ),
    ),
  );
};

van.add(document.getElementById("app"), App());
