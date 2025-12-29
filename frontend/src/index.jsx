// src/index.jsx
import "./index.css";
import { render } from "solid-js/web";
import { Router, Route } from "@solidjs/router";
import { lazy, Show } from "solid-js";
import { session, authReady } from "./lib/auth"; // Import authReady
import DashboardLayout from "./layouts/DashboardLayout";

// Lazy load pages
const Dashboard = lazy(() => import("./pages/Dashboard"));
const Login = lazy(() => import("./pages/Login"));
const Signup = lazy(() => import("./pages/Signup"));
const Team = lazy(() => import("./pages/Team"));
const Settings = lazy(() => import("./pages/Settings"));

// CRM Pages
const Deals = lazy(() => import("./pages/crm/Deals"));
const Contacts = lazy(() => import("./pages/crm/Contacts"));
const Companies = lazy(() => import("./pages/crm/Companies"));

// Auth Guard Wrapper
const Protected = (props) => {
  return (
    <Show
      when={authReady()}
      fallback={
        <div class="h-screen flex items-center justify-center">Loading...</div>
      }
    >
      <Show when={session()} fallback={<Login />}>
        <DashboardLayout>{props.children}</DashboardLayout>
      </Show>
    </Show>
  );
};

render(
  () => (
    <Router>
      <Route path="/login" component={Login} />
      <Route path="/signup" component={Signup} />
      <Route path="/" component={Protected}>
        <Route path="/" component={Dashboard} />
        <Route path="/deals" component={Deals} />
        <Route path="/contacts" component={Contacts} />
        <Route path="/companies" component={Companies} />
        <Route path="/team" component={Team} />
        <Route path="/settings" component={Settings} />
      </Route>
    </Router>
  ),
  document.getElementById("root")
);
