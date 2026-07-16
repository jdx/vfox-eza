local http = require("http")
local json = require("json")

local util = {}

local function version_parts(version)
  local major, minor, patch = version:match("^(%d+)%.(%d+)%.(%d+)$")
  if not major then
    return nil
  end
  return { tonumber(major), tonumber(minor), tonumber(patch) }
end

local function version_gt(a, b)
  local av = version_parts(a.version)
  local bv = version_parts(b.version)
  if not av or not bv then
    return a.version > b.version
  end
  for i = 1, 3 do
    if av[i] ~= bv[i] then
      return av[i] > bv[i]
    end
  end
  return false
end

local function github_headers()
  local headers = {
    ["Accept"] = "application/vnd.github+json",
    ["X-GitHub-Api-Version"] = "2022-11-28",
  }
  local token = os.getenv("GITHUB_TOKEN")
  if token and token ~= "" then
    headers["Authorization"] = "Bearer " .. token
  end
  return headers
end

function util.get_versions()
  local resp, err = http.get({
    url = "https://api.github.com/repos/cargo-bins/cargo-quickinstall/git/matching-refs/tags/eza-",
    headers = github_headers(),
  })
  if err ~= nil then
    error("failed to fetch eza versions: " .. err)
  end
  if resp.status_code ~= 200 then
    error("failed to fetch eza versions: GitHub API returned status " .. resp.status_code)
  end

  local versions = {}
  for _, ref in ipairs(json.decode(resp.body)) do
    local version = ref.ref:match("^refs/tags/eza%-(.+)$")
    if version and version_parts(version) then
      table.insert(versions, { version = version })
    end
  end
  table.sort(versions, version_gt)
  return versions
end

local targets = {
  darwin = {
    amd64 = "x86_64-apple-darwin",
    arm64 = "aarch64-apple-darwin",
  },
  linux = {
    amd64 = "x86_64-unknown-linux-gnu",
    arm64 = "aarch64-unknown-linux-gnu",
    arm = "armv7-unknown-linux-gnueabihf",
  },
  windows = {
    amd64 = "x86_64-pc-windows-msvc",
    arm64 = "aarch64-pc-windows-msvc",
  },
}

function util.download_url(version)
  local os_targets = targets[OS_TYPE]
  local target = os_targets and os_targets[ARCH_TYPE]
  if not target then
    error("unsupported platform: " .. tostring(OS_TYPE) .. "-" .. tostring(ARCH_TYPE))
  end

  local filename = string.format("eza-%s-%s.tar.gz", version, target)
  return string.format(
    "https://github.com/cargo-bins/cargo-quickinstall/releases/download/eza-%s/%s",
    version,
    filename
  )
end

return util
