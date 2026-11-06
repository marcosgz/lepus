export class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

async function request(path, params = {}) {
  const search = new URLSearchParams(params).toString();
  let response;
  try {
    response = await fetch(`api/${path}${search ? `?${search}` : ""}`, { credentials: "same-origin", headers: { Accept: "application/json" } });
  } catch {
    throw new ApiError(0, "The dashboard could not reach the server");
  }
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new ApiError(response.status, data.error || `Request failed (${response.status})`);
  return data;
}

export const api = {
  meta: () => request("meta"),
  topology: () => request("topology"),
  overview: (age) => request("overview", { age }),
  processes: () => request("processes"),
  connections: () => request("connections")
};
