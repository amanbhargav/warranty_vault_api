class ProductWarranty < ApplicationRecord
  belongs_to :invoice

  # Validations
  validates :component_name, presence: true, length: { maximum: 100 }
  validates :warranty_months, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 600 } # Max 50 years
  validates :invoice_id, uniqueness: { scope: :component_name, message: "can only have one warranty per component" }

  # Callbacks
  after_save :schedule_reminder, if: :should_schedule_reminder?
  before_destroy :cancel_reminder

  # Scopes
  scope :active, -> { where("product_warranties.expires_at > ?", Date.current).order("product_warranties.expires_at ASC") }
  scope :expiring_soon, -> { where("product_warranties.expires_at BETWEEN ? AND ?", Date.current, Date.current + 30.days).order("product_warranties.expires_at ASC") }
  scope :expired, -> { where("product_warranties.expires_at < ?", Date.current).order("product_warranties.expires_at DESC") }
  scope :due_for_reminder, -> { where(product_warranties: { expires_at: Date.current..(Date.current + 1.month), reminder_sent: false }) }
  scope :by_component, -> { order(component_name: :asc) }

  # Named scopes for specific components
  scope :product, -> { where(component_name: "product") }
  scope :compressor, -> { where(component_name: "compressor") }
  scope :battery, -> { where(component_name: "battery") }

  # Component name validation (common warranty components)
  VALID_COMPONENTS = %w[
    product compressor battery motor panel display pump filter
    heating cooling electrical plumbing structural appliance
  ].freeze

  validate :component_name_is_valid

  # Calculate if warranty is expiring soon
  def expiring_soon?(days = 30)
    expires_at && (expires_at - Date.current).to_i <= days.days && !expired?
  end

  # Check if warranty is expired
  def expired?
    expires_at && expires_at < Date.current
  end

  # Check if warranty is active
  def active?
    expires_at && expires_at > Date.current
  end

  # Get days remaining
  def days_remaining
    return nil unless expires_at
    [(expires_at - Date.current).to_i, 0].max
  end

  # Get formatted warranty duration
  def formatted_duration
    return "N/A" unless warranty_months

    if warranty_months >= 12 && (warranty_months % 12).zero?
      years = warranty_months / 12
      "#{years} year#{'s' if years > 1}"
    else
      "#{warranty_months} month#{'s' if warranty_months > 1}"
    end
  end

  # Get component display name
  def component_display_name
    component_name.humanize.titleize
  end

  # Mark reminder as sent
  def mark_reminder_sent!
    update!(reminder_sent: true, last_reminder_sent_at: Time.current)
  end

  # Reset reminder status (for manual re-notification)
  def reset_reminder!
    update!(reminder_sent: false, last_reminder_sent_at: nil)
  end

  # Check if reminder should be scheduled
  def should_schedule_reminder?
    persisted? && expires_at.present? && !reminder_sent
  end

  # Schedule reminder job for this warranty
  def schedule_reminder
    WarrantyReminderService.new(self).schedule_reminder
  rescue => e
    Rails.logger.error "[ProductWarranty] Failed to schedule reminder: #{e.message}"
    # Don't raise - scheduling failure shouldn't break the save
  end

  # Cancel scheduled reminder (called before destroy)
  def cancel_reminder
    WarrantyReminderService.new(self).cancel_reminder
  end

  private

  def component_name_is_valid
    # Allow any component name but warn if not in common list
    # This is flexible for various product types
    unless VALID_COMPONENTS.include?(component_name.downcase)
      # Log warning but don't invalidate - allows flexibility
      Rails.logger.warn "[ProductWarranty] Unusual component name: #{component_name}"
    end
  end
end
