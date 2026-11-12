// Installed via `node --import` before tools/bake_data.mjs evaluates the prototype.
import { register } from "node:module";

register(new URL("./ts_resolve.mjs", import.meta.url).href, {
  parentURL: import.meta.url,
});
