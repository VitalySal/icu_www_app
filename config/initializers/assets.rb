# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = '1.0'

# Add additional assets to the asset load path
# Rails.application.config.assets.paths << Emoji.images_path

# Precompile additional assets.
# application.js, application.css, and all non-JS/CSS in app/assets folder are already added.
# --- OUTDATED AS OF SPROCKETS 4 ---
# Rails.application.config.assets.precompile += User::THEMES.reject{ |theme| theme == "Bootstrap" }.map{ |theme| "#{theme.downcase}.min.css"}
# Rails.application.config.assets.precompile += %w/spin.js payment.js switch_from_tls.js/
# Rails.application.config.assets.precompile += %w(pgnyui.js pgnviewer.js)