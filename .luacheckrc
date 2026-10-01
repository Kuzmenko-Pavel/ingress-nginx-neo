std = 'ngx_lua'
max_line_length = 100
max_comment_line_length = false
globals = {
  'lua_ingress',
  'configuration',
  'balancer',
  'monitor',
  'certificate',
  'tcp_udp_configuration',
  'tcp_udp_balancer',
}
exclude_files = {'./rootfs/etc/nginx/lua/test/**/*.lua'}
files["rootfs/etc/nginx/lua/lua_ingress.lua"] = {
  ignore = { "122" },
}
