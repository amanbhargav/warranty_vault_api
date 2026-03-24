# frozen_string_literal: true

require "test_helper"

class WarrantyReminderServiceTest < ActiveSupport::TestCase
  include WarrantyTestHelpers

  setup do
    @user = User.create!(
      email: "test@example.com",
      password_digest: BCrypt::Password.create("password123"),
      first_name: "Test",
      last_name: "User"
    )

    @invoice = Invoice.create!(
      user: @user,
      product_name: "Test Product",
      brand: "Test Brand",
      purchase_date: Date.current,
      warranty_duration: 12,
      ocr_status: :completed
    )

    @warranty = ProductWarranty.create!(
      invoice: @invoice,
      component_name: "product",
      warranty_months: 12,
      expires_at: 60.days.from_now,
      purchase_date: Date.current,
      reminder_sent: false
    )
  end

  test "should schedule reminder for future date" do
    service = WarrantyReminderService.new(@warranty)

    assert service.schedule_reminder

    # Should enqueue job with wait_until
    assert_enqueued_jobs 1
  end

  test "should send immediate reminder if expiry is within 30 days" do
    @warranty.update!(expires_at: 20.days.from_now)
    service = WarrantyReminderService.new(@warranty)

    assert service.schedule_reminder

    # Should send immediately since reminder date is in the past
    assert_enqueued_jobs 1
  end

  test "should not schedule if reminder already sent" do
    @warranty.update!(reminder_sent: true)
    service = WarrantyReminderService.new(@warranty)

    refute service.schedule_reminder
    assert_no_enqueued_jobs
  end

  test "should not schedule if expires_at is nil" do
    @warranty.update!(expires_at: nil)
    service = WarrantyReminderService.new(@warranty)

    refute service.schedule_reminder
    assert_no_enqueued_jobs
  end

  test "should send immediate reminder if expiry date is in past" do
    @warranty.update!(expires_at: 10.days.ago)
    service = WarrantyReminderService.new(@warranty)

    assert service.schedule_reminder
    assert_enqueued_jobs 1
  end

  test "should reschedule reminder" do
    @warranty.update!(reminder_sent: true)
    service = WarrantyReminderService.new(@warranty)

    service.reschedule_reminder

    @warranty.reload
    refute @warranty.reminder_sent
    assert_enqueued_jobs 1
  end

  test "class method schedule_for_invoice should schedule all warranties" do
    warranty2 = ProductWarranty.create!(
      invoice: @invoice,
      component_name: "battery",
      warranty_months: 6,
      expires_at: 45.days.from_now,
      purchase_date: Date.current,
      reminder_sent: false
    )

    WarrantyReminderService.schedule_for_invoice(@invoice)

    # Should schedule both warranties
    assert_enqueued_jobs 2
  end

  test "class method process_due_reminders should process warranties due for reminder" do
    # Create warranty due for reminder
    due_warranty = ProductWarranty.create!(
      invoice: @invoice,
      component_name: "motor",
      warranty_months: 1,
      expires_at: 25.days.from_now,
      purchase_date: Date.current,
      reminder_sent: false
    )

    count = WarrantyReminderService.process_due_reminders

    assert count >= 1
  end
end
