class Club < ApplicationRecord
  include Geocodable
  include Journalable
  include Normalizable
  include Pageable

  journalize %w[name web meet address district city county lat long contact email phone active], "/clubs/%d"

  has_many :players

  default_scope { order(:name) }
  scope :active, -> { where(active: true) }
  scope :junior_only, -> { where(junior_only: true) }
  scope :junior, -> { where("junior_only = true or has_junior_section = true") }
  scope :with_geocodes, -> { where.not(lat: nil).where.not(long: nil) }

  before_validation :normalize_attributes

  validate :has_contact_method

  validates :name, presence: true, uniqueness: true
  validates :web, url: true, allow_nil: true
  validates :meet, :address, :district, presence: true, allow_nil: true
  validates :city, presence: true
  validates :county, inclusion: { in: Ireland.counties, message: "invalid county" }
  validates :lat,  numericality: { greater_than:  51.2, less_than: 55.6, message: "must be between 51.2 and 55.6" }, allow_nil: true
  validates :long, numericality: { greater_than: -10.6, less_than: -5.3, message: "must be between -10.6 and -5.3" }, allow_nil: true
  validates :contact, presence: true, allow_nil: true
  validates :email, email: true, allow_nil: true
  validates :phone, format: { with: /\d{3}/ }, allow_nil: true
  validates :active, inclusion: { in: [true, false] }

  def province
    Ireland.province(county)
  end

  def contactable?
    phone.present? || email.present? || web.present?
  end

  def self.search(params, path)
    matches = all
    matches = matches.where("name LIKE ?", "%#{params[:name].squish}%") if params[:name].present?
    matches = matches.where("city LIKE ?", "%#{params[:city]}%") if params[:city].present?
    matches = matches.where(county: params[:county]) if Ireland.county?(params[:county])
    matches = matches.where("county IN (?)", Ireland.counties(params[:province])) if Ireland.province?(params[:province])
    matches = matches.where("contact LIKE ?", "%#{params[:contact]}%") if params[:contact].present?
    case params[:active]
    when "true", nil then matches = matches.where(active: true)
    when "false"     then matches = matches.where(active: false)
    end
    case params[:junior]
      when "junior_only" then matches = matches.where(junior_only: true)
      when "has_junior_section" then matches = matches.where(has_junior_section: true)
    end
    paginate(matches, params, path)
  end

  def geocodes?
    active && lat.present? && long.present?
  end

  def location
    location = []
    location << address  if address
    location << district if district
    location << city     if city
    location << I18n.t("club.co") + " " + I18n.t("ireland.co.#{county}")
    location << I18n.t("ireland.prov.#{province}")
    location.join(', ')
  end

  private

  def has_contact_method
    if active && !contactable?
    #   errors[:base] << "An active club must have at least one contact method (phone, email or web)"
      errors.add(:base, "An active club must have at least one contact method (phone, email or web)")
    end
  end

  def normalize_attributes
    normalize_blanks(:name, :web, :meet, :address, :district, :city, :lat, :long, :contact, :email, :phone)
    if web.present? && web.match(/\A[^.\/\s:]+(\.[^.\/\s:]+){1,}[^\s]+/)
      self.web = "http://#{web}"
    end
  end
end
