class User < ActiveRecord::Base
  include Journalable
  include Pageable

  journalize [:status, :encrypted_password, :roles, :verified_at], "/admin/users/%d"

  attr_accessor :password, :ticket

  OK = "OK"
  # The tester role is used to show new functionality
  ROLES = %w[admin tester calendar editor inspector membership translator treasurer]
  MINIMUM_PASSWORD_LENGTH = 6
  THEMES = %w[Cerulean Cosmo Cyborg Darkly Flatly Journal Lumen Superhero Paper Readable Sandstone Simplex Slate Spacelab United Yeti]
  DEFAULT_THEME = "Flatly"
  LOCALES = %w[en ga]
  SessionError = Class.new(RuntimeError)

  has_many :articles, dependent: :nullify
  has_many :carts, dependent: :nullify
  has_many :news, dependent: :nullify
  has_many :logins, dependent: :destroy
  has_many :refunds, dependent: :nullify
  has_many :pgns, dependent: :nullify
  belongs_to :player

  default_scope { order(:email) }
  scope :include_player, -> { includes(:player) }

  before_validation :canonicalize_roles, :dont_remove_the_last_admin, :update_password_if_present, :asshole_check

  validates :email, uniqueness: { case_sensitive: false }, email: true
  validates :encrypted_password, :expires_on, :status, presence: true
  validates :salt, length: { is: 32 }
  validates :player_id, numericality: { only_integer: true, greater_than: 0 }
  validates :roles, format: { with: /\A(#{ROLES.join('|')})( (#{ROLES.join('|')}))*\z/ }, allow_nil: true
  validates :theme, inclusion: { in: THEMES }, allow_nil: true
  validates :locale, inclusion: { in: LOCALES }

  def name
    player.name
  end

  def signature
    "#{name} (#{email}/#{id})"
  end

  def valid_password?(password)
    encrypted_password == User.encrypt_password(password, salt)
  end

  def status_ok?
    status == OK
  end

  def verified?
    verified_at ? true : false
  end

  def verify
    verified? ? "yes" : "no"
  end

  def verify=(action)
    case action
    when "yes"
      self.verified_at = Time.now unless verified?
    when "no"
      self.verified_at = nil if verified?
    end
    verify
  end

  def subscribed?
    not expires_on.past?
  end

  def season_ticket
    t = SeasonTicket.new(player_id, expires_on)
    t.valid? ? t.to_s : t.error
  end

  # Updates the last_used_at attribute with the current time.
  def used_site_now
    self.update_attributes(last_used_at: Time.now)
  end

  # Cater for a theme getting removed, as Ameila was in Aug 2014 after Bootswatch announced they were dropping it.
  def preferred_theme
    theme.present? && THEMES.include?(theme) ? theme : DEFAULT_THEME
  end

  ROLES.each do |role|
    define_method "#{role}?" do
      roles.present? && (roles.include?(role) || roles.include?("admin"))
    end
  end

  def human_roles(options={})
    return "" if roles.blank?
    roles.split(" ").map do |role|
      ROLES.include?(role) ? I18n.t("user.role.#{role}", options) : role
    end.join(" ")
  end

  def guest?; false end
  def member?; true end

  class Guest
    def id; 0 end
    def name; "Guest" end
    def guest?; true end
    def member?; false end
    def player; nil end
    def roles; nil end
    def preferred_theme; DEFAULT_THEME end
    def used_site_now; end
    User::ROLES.each do |role|
      define_method "#{role}?" do
        false
      end
    end
  end

  def self.search(params, path)
    matches = include_player.references(:players)
    if params[:last_name].present? || params[:first_name].present?
      matches = matches.joins(:player)
      matches = matches.where("players.last_name LIKE ?", "%#{params[:last_name]}%") if params[:last_name].present?
      matches = matches.where("players.first_name LIKE ?", "%#{params[:first_name]}%") if params[:first_name].present?
    end
    matches = matches.where("users.email LIKE ?", "%#{params[:email]}%") if params[:email].present?
    matches = matches.where(status: User::OK) if params[:status] == "OK"
    matches = matches.where(player_id: params[:player_id].to_i) if params[:player_id].to_i > 0
    matches = matches.where.not(status: User::OK) if params[:status] == "Not OK"
    case
    when params[:role] == "some"       then matches = matches.where("roles IS NOT NULL")
    when params[:role] == "none"       then matches = matches.where("roles IS NULL")
    when ROLES.include?(params[:role]) then matches = matches.where("roles LIKE ?", "%#{params[:role]}%")
    end
    case params[:expiry]
    when "Active"   then matches = matches.where("expires_on >= ?", Date.today.to_s)
    when "Expired"  then matches = matches.where("expires_on <  ?", Date.today.to_s)
    when "Extended" then matches = matches.where("expires_on >= ?", Date.today.years_since(2).end_of_year)
    end
    case params[:verify]
    when "Verified"   then matches = matches.where("verified_at IS NOT NULL")
    when "Unverified" then matches = matches.where(verified_at: nil)
    end
    paginate(matches, params, path)
  end

  def self.encrypt_password(password, salt)
    eval(Rails.application.secrets.crypt["password"])
  end

  def self.random_salt
    Digest::MD5.hexdigest(rand(1000000).to_s + Time.now.to_s)
  end

  def self.authenticate!(email, password, ip="127.0.0.1")
    raise SessionError.new("enter_email") if email.blank?
    raise SessionError.new("enter_password") if password.blank?
    user = User.find_by(email: email)
    self.bad_login(ip, email, password)            unless user
    user.add_login(ip, "invalid_password")         unless user.valid_password?(password)
    user.add_login(ip, "unverified_email")         unless user.verified?
    user.add_login(ip, "account_disabled")         unless user.status_ok?
    user.add_login(ip, "subscription_expired")     unless user.subscribed?
    user.add_login(ip)
  end

  def self.bad_login(ip, email, password)
    BadLogin.new_record(email, password, ip)
    raise SessionError.new("invalid_email")
  end

  def add_login(ip, error=nil)
    logins.create(ip: ip, error: error, roles: roles)
    raise SessionError.new(error) if error
    self
  end

  def self.locale?(locale)
    LOCALES.include?(locale.to_s)
  end

  def reason_to_not_delete
    case
    when roles.present?   then "has special roles"
    when logins.count > 0 then "has recorded logins"
    else false
    end
  end

  # Prepare a new user record for further validation and possible saving where the virtual "ticket" attribute contains a season ticket value.
  # If everything is OK set an appropriate expiry date and return true. Otherwise add errors (for display) and return false.
  def sign_up
    return false unless new_record?
    t = SeasonTicket.new(ticket)
    if player
      if t.valid?
        if t.valid?(player.id)
          if t.valid?(player.id, Date.today)
            if player.users.where(email: email, verified_at: nil).empty?
              if password.present?
                self.expires_on = t.expires_on
                return true
              else
                errors.add(:password, I18n.t("errors.messages.invalid"))
              end
            else
              errors.add(:email, I18n.t("user.incomplete_registration"))
            end
          else
            errors.add(:ticket, I18n.t("errors.attributes.ticket.expired"))
          end
        else
          errors.add(:ticket, I18n.t("errors.attributes.ticket.mismatch"))
        end
      else
        errors.add(:ticket, I18n.t("errors.messages.invalid"))
      end
    else
      errors.add(:player_id, I18n.t("errors.messages.invalid"))
    end
    false
  end

  def verification_param
    eval(Rails.application.secrets.crypt["verifier"])
  end

  def change_password(old, new_1, new_2)
    if valid_password?(old)
      if new_1.present?
        if new_1 == new_2
          self.password = new_1
          update_password_if_present
          if errors[:password].empty?
            save!
            nil
          else
            "#{I18n.t('user.new_password_1')} #{errors[:password].first}"
          end
        else
          I18n.t("user.new_password_mismatch")
        end
      else
        "#{I18n.t('user.new_password_1')} #{I18n.t('errors.messages.blank')}"
      end
    else
      "#{I18n.t('user.old_password')} #{I18n.t('errors.messages.invalid')}"
    end
  rescue => e
    Failure.log("ChangePasswordFailure", exception: e, user_id: id)
    I18n.t("errors.alerts.application")
  end

  # Resets reset password token and send reset password instructions by email.
  # Returns the token sent in the e-mail.
  def send_reset_password_instructions
    token = set_reset_password_token
    send_reset_password_instructions_notification(token)

    token
  end

  def reset_password_period_valid?
    reset_password_sent_at && reset_password_sent_at.utc >= 24.hours.ago
  end

  # Removes reset_password token
  def clear_reset_password_token
    self.reset_password_token = nil
    self.reset_password_sent_at = nil
  end

  def set_reset_password_token
    while true
      token = SecureRandom.hex(32)
      break unless User.where(reset_password_token: token).exists?
    end

    self.reset_password_token   = token
    self.reset_password_sent_at = Time.now.utc
    self.save(validate: false)
    token
  end

  def send_reset_password_instructions_notification(token)
    IcuMailer.forgot_password(id, token).deliver_now
  end

  private

  def canonicalize_roles
    if roles.present?
      _roles = roles
      _roles = _roles.scan(/\w+/) unless _roles.is_a?(Array)
      _roles = _roles.select { |r| User::ROLES.include?(r) }
      if _roles.include?("admin")
        self.roles = "admin"
      elsif _roles.empty?
        self.roles = nil
      else
        self.roles = _roles.sort.join(" ")
      end
    else
      self.roles = nil
    end
  end

  def dont_remove_the_last_admin
    if changed?
      if changed_attributes["roles"] == "admin"
        count = User.where(roles: "admin").where.not(id: id).count
        errors.add(:roles, "Can't remove the last #{I18n.t('user.role.admin')}") unless count > 0
      end
    end
  end

  def update_password_if_present
    if password.present?
      if password.length >= MINIMUM_PASSWORD_LENGTH
        if password.match(/\d/)
          self.salt = User.random_salt
          self.encrypted_password = User.encrypt_password(password, salt)
        else
          errors.add :password, I18n.t("errors.attributes.password.digits")
        end
      else
        errors.add :password, I18n.t("errors.attributes.password.length", minimum: MINIMUM_PASSWORD_LENGTH)
      end
    end
  end

  def asshole_check
    return if new_record? || roles.blank?
    if [11, 295, 1354, 1733, 5198, 5601, 6141].include? player_id
      errors.add(:roles, I18n.t("user.role_denied"))
    end
  end
end
