import "./index.css";
import { render } from "solid-js/web";
import { Router, Route } from "@solidjs/router";
import { lazy, Show } from "solid-js";
import { session } from "./lib/auth";
import DashboardLayout from "./layouts/DashboardLayout";

// Lazy load pages
const Dashboard = lazy(() => import("./pages/Dashboard"));
const Projects = lazy(() => import("./pages/Projects"));
const ProjectDetail = lazy(() => import("./pages/ProjectDetail"));
const Team = lazy(() => import("./pages/Team"));
const Login = lazy(() => import("./pages/Login"));

// Auth Guard Wrapper
const Protected = (props) => {
  return (
    <Show when={session()} fallback={<Login />}>
      <DashboardLayout>{props.children}</DashboardLayout>
    </Show>
  );
};

render(
  () => (
    <Router>
      <Route path="/login" component={Login} />

      <Route path="/" component={Protected}>
        <Route path="/" component={Dashboard} />
        <Route path="/projects" component={Projects} />
        <Route path="/projects/:id" component={ProjectDetail} />
        <Route path="/team" component={Team} />
        <Route
          path="/settings"
          component={() => <div>Settings Placeholder</div>}
        />
      </Route>
    </Router>
  ),
  document.getElementById("root")
);
