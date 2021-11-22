lib: site: config: version:
with lib;
let
  db-config = optionalString (config.database != null)
    ''
      type = "${config.database.type}"
      pdo_dsn = "${config.database.type}:host=${config.database.hostname};port=${toString config.database.port};dbname=${config.database.name}"
      pdo_user = "${config.database.user}"
      pdo_password = "${fileContents config.database.password-file}"
    '';

in ''
  [webmail]
  title = "${config.title}"
  loading_description = "${config.title}"
  favicon_url = "https://${site}/favicon.ico"
  theme = "${config.theme}"
  allow_themes = On
  allow_user_background = Off
  language = "en"
  language_admin = "en"
  allow_languages_on_settings = On
  allow_additional_accounts = On
  allow_additional_identities = On
  messages_per_page = ${toString config.messages-per-page}
  attachment_size_limit = ${toString config.max-upload-size}

  [interface]
  show_attachment_thumbnail = On
  new_move_to_folder_button = On

  [branding]

  [contacts]
  enable = On
  allow_sync = On
  sync_interval = 20
  suggestions_limit = 10
  ${db-config}

  [security]
  csrf_protection = On
  custom_server_signature = "RainLoop"
  x_frame_options_header = ""
  openpgp = On

  admin_login = "admin"
  admin_password = ""
  allow_admin_panel = Off
  allow_two_factor_auth = On
  force_two_factor_auth = Off
  hide_x_mailer_header = Off
  admin_panel_host = ""
  admin_panel_key = "admin"
  content_security_policy = ""
  core_install_access_domain = ""

  [login]
  default_domain = "${config.domain}"
  allow_languages_on_login = On
  determine_user_language = On
  determine_user_domain = Off
  welcome_page = Off
  hide_submit_button = On

  [plugins]
  enable = Off

  [defaults]
  view_editor_type = "${config.edit-mode}"
  view_layout = ${if (config.layout-mode == "bottom") then "2" else "1"}
  contacts_autosave = On
  mail_use_threads = ${if config.enable-threading then "On" else "Off"}
  allow_draft_autosave = On
  mail_reply_same_folder = Off
  show_images = On

  [logs]
  enable = ${if config.debug then "On" else "Off"}

  [debug]
  enable = ${if config.debug then "On" else "Off"}
  hide_passwords = On
  filename = "log-{date:Y-m-d}.txt"

  [social]
  google_enable = Off
  fb_enable = Off
  twitter_enable = Off
  dropbox_enable = Off

  [cache]
  enable = On
  index = "v1"
  fast_cache_driver = "files"
  fast_cache_index = "v1"
  http = On
  http_expires = 3600
  server_uids = On

  [labs]
  allow_mobile_version = ${if config.enable-mobile then "On" else "Off"}
  check_new_password_strength = On
  allow_gravatar = On
  allow_prefetch = On
  allow_smart_html_links = On
  cache_system_data = On
  date_from_headers = On
  autocreate_system_folders = On
  allow_ctrl_enter_on_compose = On
  favicon_status = On
  use_local_proxy_for_external_images = On
  detect_image_exif_orientation = On

  [version]
  current = "${version}"
''
