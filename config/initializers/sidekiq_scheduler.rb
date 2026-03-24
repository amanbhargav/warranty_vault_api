# frozen_string_literal: true

# Sidekiq Scheduler configuration for recurring jobs
# Configure hourly app reminder job

require "sidekiq-scheduler"

Sidekiq.configure_server do |config|
  config.on(:startup) do
    Sidekiq::Scheduler.enabled = true
    Sidekiq.schedule = {
      # Hourly app reminder - runs every hour
      "hourly_app_reminder" => {
        "cron" => "0 * * * *",  # Every hour at minute 0
        "class" => "HourlyAppReminderJob",
        "queue" => "default",
        "description" => "Send hourly app reminders to users about warranty tracking"
      }
    }

    Sidekiq::Scheduler.reload_schedule!
  end
end

Sidekiq.configure_client do |config|
  config.on(:startup) do
    Sidekiq::Scheduler.enabled = true
  end
end
