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

local sources = {
  darwin = {
    repository = "cargo-bins/cargo-quickinstall",
    tag_prefix = "eza-",
    ref_pattern = "^refs/tags/eza%-(.+)$",
    targets = {
      amd64 = "x86_64-apple-darwin",
      arm64 = "aarch64-apple-darwin",
    },
    filename = function(version, target)
      return string.format("eza-%s-%s.tar.gz", version, target)
    end,
  },
  linux = {
    repository = "eza-community/eza",
    tag_prefix = "v",
    ref_pattern = "^refs/tags/v(.+)$",
    list_releases = true,
    targets = {
      amd64 = "x86_64-unknown-linux-gnu",
      arm64 = "aarch64-unknown-linux-gnu",
      arm = "arm-unknown-linux-gnueabihf",
    },
    filename = function(_, target)
      return string.format("eza_%s.tar.gz", target)
    end,
  },
  windows = {
    repository = "cargo-bins/cargo-quickinstall",
    tag_prefix = "eza-",
    ref_pattern = "^refs/tags/eza%-(.+)$",
    targets = {
      amd64 = "x86_64-pc-windows-msvc",
      arm64 = "aarch64-pc-windows-msvc",
    },
    filename = function(version, target)
      return string.format("eza-%s-%s.tar.gz", version, target)
    end,
  },
}

function util.get_versions()
  local source = sources[OS_TYPE]
  local target = source and source.targets[ARCH_TYPE]
  if not target then
    error("unsupported platform: " .. tostring(OS_TYPE) .. "-" .. tostring(ARCH_TYPE))
  end

  local versions = {}
  local page = 1
  repeat
    local path
    if source.list_releases then
      path = string.format("releases?per_page=100&page=%d", page)
    else
      path = "git/matching-refs/tags/" .. source.tag_prefix
    end
    local resp, err = http.get({
      url = string.format("https://api.github.com/repos/%s/%s", source.repository, path),
      headers = github_headers(),
    })
    if err ~= nil then
      error("failed to fetch eza versions: " .. err)
    end
    if resp.status_code ~= 200 then
      error("failed to fetch eza versions: GitHub API returned status " .. resp.status_code)
    end

    local entries = json.decode(resp.body)
    for _, entry in ipairs(entries) do
      local ref = entry.ref or ("refs/tags/" .. entry.tag_name)
      local version = ref:match(source.ref_pattern)
      local filename = version and source.filename(version, target)
      local available = not source.list_releases
      for _, asset in ipairs(entry.assets or {}) do
        if asset.name == filename then
          available = true
          break
        end
      end
      if available and version and version_parts(version) then
        table.insert(versions, { version = version })
      end
    end
    page = page + 1
    if not source.list_releases or #entries < 100 then
      break
    end
  until false

  table.sort(versions, version_gt)
  return versions
end

function util.download_url(version)
  local source = sources[OS_TYPE]
  local target = source and source.targets[ARCH_TYPE]
  if not target then
    error("unsupported platform: " .. tostring(OS_TYPE) .. "-" .. tostring(ARCH_TYPE))
  end

  local filename = source.filename(version, target)
  return string.format(
    "https://github.com/%s/releases/download/%s%s/%s",
    source.repository,
    source.tag_prefix,
    version,
    filename
  )
end

return util
