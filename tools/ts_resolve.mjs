// Resolve extensionless imports inside the Game_test snapshot (`from '../shapes'`).
// Type-only imports are erased by Node's strip-types loader; this hook only appends `.ts`.

const HAS_EXT = /\.(?:ts|mts|cts|js|mjs|cjs|json|node|wasm)$/;

export async function resolve(specifier, context, nextResolve) {
  const relative = specifier.startsWith(".") || specifier.startsWith("/");
  if (relative && !HAS_EXT.test(specifier)) {
    return nextResolve(specifier + ".ts", context);
  }
  return nextResolve(specifier, context);
}
