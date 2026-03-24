class Invoice < ApplicationRecord
  belongs_to :user
  has_many :product_warranties, dependent: :destroy

  has_one_attached :file

  enum :warranty_status, { active: 0, expiring_soon: 1, expired: 2 }
  enum :ocr_status, { pending: 0, processing: 1, completed: 2, failed: 3 }, default: :pending

  # Validations are conditional based on OCR status
  # Allow initial save without data for OCR processing flow
  validates :product_name, presence: true, if: :ocr_completed_or_manual_entry?
  validates :purchase_date, presence: true, if: :ocr_completed_or_manual_entry?
  validates :amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :warranty_duration, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 120 }, allow_nil: true

  before_save :calculate_expiry_date
  before_save :update_warranty_status
  after_save :schedule_warranty_reminders, if: :should_schedule_reminders?

  scope :active, -> { where(warranty_status: :active) }
  scope :expiring_soon, -> { where(warranty_status: :expiring_soon) }
  scope :expired, -> { where(warranty_status: :expired) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_purchase_date, -> { order(purchase_date: :desc) }
  scope :search, ->(query) {
    where("product_name ILIKE ? OR brand ILIKE ? OR seller ILIKE ? OR category ILIKE ?",
          "%#{query}%", "%#{query}%", "%#{query}%", "%#{query}%")
  }
  scope :with_expiring_warranties, -> {
    joins(:product_warranties)
      .where("product_warranties.expires_at BETWEEN ? AND ?", Date.current, 30.days.from_now)
      .distinct
  }

  # Calculate warranty expiry date
  def calculate_expiry_date
    self.expires_at = purchase_date + warranty_duration.to_i.months if purchase_date && warranty_duration
  end

  # Update warranty status based on expiry date
  def update_warranty_status
    return unless expires_at

    days_until_expiry = (expires_at - Date.current).to_i

    if days_until_expiry < 0
      self.warranty_status = :expired
    elsif days_until_expiry <= 30
      self.warranty_status = :expiring_soon
    else
      self.warranty_status = :active
    end
  end

  # Check if warranty is expiring within given days
  def expiring_within?(days = 30)
    expires_at && (expires_at - Date.current).to_i <= days
  end

  # Get days remaining on warranty
  def days_remaining
    return nil unless expires_at
    [ (expires_at - Date.current).to_i, 0 ].max
  end

  # Get formatted amount
  def formatted_amount
    amount ? "₨. #{amount.to_f.round(2)}" : "N/A"
  end

  # Get OCR data as hash
  def ocr_data_hash
    return {} unless ocr_data.present?
    JSON.parse(ocr_data)
  rescue JSON::ParserError
    {}
  end

  # Update from OCR data
  def update_from_ocr(data)
    self.product_name = data["product_name"] || product_name
    self.brand        = data["brand"]         || brand
    self.model_number = data["model_number"]  || model_number
    self.seller       = data["seller"]        || seller
    self.amount       = data["amount"]        || amount
    self.purchase_date = Date.parse(data["purchase_date"]) if data["purchase_date"].present?
    self.warranty_duration = data["warranty_duration"] || warranty_duration
    self.category     = data["category"]      || category
  end

  # Mark OCR as completed and validate data
  def mark_ocr_completed
    self.ocr_status = :completed
    save!(validate: true)
  end

  # Mark OCR as failed
  def mark_ocr_failed(error_message = nil)
    self.ocr_status = :failed
    self.ocr_error_message = error_message
    save!(validate: false)
  end

  # Check if validations should run
  def ocr_completed_or_manual_entry?
    completed? || ocr_data.blank?
  end

  # Check if OCR is completed
  def completed?
    ocr_status == "completed"
  end

  # Alias for backward compatibility
  alias_method :ocr_completed?, :completed?

  # Check if product enrichment is complete
  def product_enriched?
    product_enriched == true
  end

  # Check if complete processing is done
  def processing_complete?
    completed? && product_enriched?
  end

  # Get file path for OCR processing
  def file_path
    return nil unless file.attached?
    file.blob.download
  end

  # Get warranty summary for dashboard
  def warranty_summary
    {
      id: id,
      product_name: product_name,
      brand: brand,
      main_warranty: {
        expires_at: expires_at,
        days_remaining: days_remaining,
        status: warranty_status,
        duration_months: warranty_duration
      },
      component_warranties: product_warranties.select(:component_name, :expires_at, :warranty_months).map do |pw|
        {
          component: pw.component_name,
          expires_at: pw.expires_at,
          duration_months: pw.warranty_months,
          days_remaining: pw.days_remaining,
          status: pw.active? ? "active" : (pw.expired? ? "expired" : "unknown")
        }
      end
    }
  end

  # Check if we should schedule warranty reminders
  # Only schedule if OCR is completed and we have valid warranty data
  def should_schedule_reminders?
    completed? && purchase_date.present? && warranty_duration.present? && product_warranties.any?
  end

  # Schedule reminder jobs for all warranties on this invoice
  def schedule_warranty_reminders
    WarrantyReminderService.schedule_for_invoice(self)
  rescue => e
    Rails.logger.error "[Invoice] Failed to schedule warranty reminders: #{e.message}"
    # Don't raise - scheduling failure shouldn't break the save
  end
end
