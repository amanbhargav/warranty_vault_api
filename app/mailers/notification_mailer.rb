# frozen_string_literal: true

class NotificationMailer < ApplicationMailer
  default from: ENV.fetch("SMTP_FROM", "Warranty Vault <noreply@warrantyvault.com>")

  # Send daily reminder email
  def daily_reminder(user)
    @user = user
    @dashboard_url = dashboard_url
    @upload_url = upload_url

    # Get user's warranty statistics
    @active_warranties = user.invoices.where(warranty_status: :active).count
    @expiring_soon = user.invoices.where(warranty_status: :expiring_soon).count
    @expired = user.invoices.where(warranty_status: :expired).count

    mail(
      to: user.email,
      subject: "Daily Warranty Check - #{Date.current.strftime('%B %d, %Y')}"
    )
  end

  # Send warranty expiry notification
  def warranty_expiry_notification(user, warranties)
    @user = user
    @warranties = warranties
    @dashboard_url = dashboard_url

    mail(
      to: user.email,
      subject: "Warranty Expiry Reminder - #{warranties.count} Item#{warranties.count > 1 ? 's' : ''} Expiring Soon"
    )
  end

  # Send welcome email after verification
  def welcome_email(user)
    @user = user
    @dashboard_url = dashboard_url
    @upload_url = upload_url

    mail(
      to: user.email,
      subject: "Welcome to Warranty Vault!"
    )
  end

  private

  def dashboard_url
    if Rails.env.development?
      "http://localhost:3006/dashboard"
    elsif Rails.env.production?
      "#{ENV.fetch('FRONTEND_URL', 'https://warranty-vault.com')}/dashboard"
    else
      "http://localhost:3000/dashboard"
    end
  end

  def upload_url
    if Rails.env.development?
      "http://localhost:3006/upload"
    elsif Rails.env.production?
      "#{ENV.fetch('FRONTEND_URL', 'https://warranty-vault.com')}/upload"
    else
      "http://localhost:3000/upload"
    end
  end
end
