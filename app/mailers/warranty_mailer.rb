# Mailer for warranty-related email notifications
#
# Usage:
#   WarrantyMailer.with(user:, invoice:, warranty:, days_remaining:).warranty_expiring_soon.deliver_later
#   WarrantyMailer.with(user:, invoice:, warranty:).warranty_expired.deliver_later
class WarrantyMailer < ApplicationMailer
  default from: ENV.fetch("SMTP_FROM", "noreply@warrantyvault.com")

  # Send warranty expiration reminder email (30 days before expiry)
  def warranty_expiring_soon
    @user = params[:user]
    @invoice = params[:invoice]
    @warranty = params[:warranty]
    @days_remaining = params[:days_remaining]
    @company_name = ENV.fetch("APP_NAME", "Warranty Vault")
    @support_email = ENV.fetch("SUPPORT_EMAIL", "support@warrantyvault.com")

    mail(
      to: @user.email,
      subject: build_subject,
      template_path: "warranty_mailer",
      template_name: "warranty_expiring_soon"
    )
  end

  # Send warranty expired notification email
  def warranty_expired
    @user = params[:user]
    @invoice = params[:invoice]
    @warranty = params[:warranty]
    @days_remaining = 0
    @company_name = ENV.fetch("APP_NAME", "Warranty Vault")
    @support_email = ENV.fetch("SUPPORT_EMAIL", "support@warrantyvault.com")

    mail(
      to: @user.email,
      subject: "Warranty Expired: #{@invoice.product_name}",
      template_path: "warranty_mailer",
      template_name: "warranty_expired"
    )
  end

  private

  def build_subject
    if @days_remaining <= 0
      "⚠️ Warranty Expired: #{@invoice.product_name}"
    elsif @days_remaining <= 7
      "⚠️ Urgent: #{@invoice.product_name} warranty expires in #{@days_remaining} days"
    elsif @days_remaining <= 30
      "Reminder: #{@invoice.product_name} warranty expires on #{@warranty.expires_at.strftime('%d %b %Y')}"
    else
      "Warranty Reminder: #{@invoice.product_name}"
    end
  end
end
