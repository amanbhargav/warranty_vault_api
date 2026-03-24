# Schedule file for Sidekiq-Cron
# Install with: gem install sidekiq-cron
# Then add to config/initializers/sidekiq.rb: Sidekiq::Cron::Job.load_from_hash!

# Daily warranty reminder check at 9 AM UTC
WarrantyReminderCheck:
  cron: "0 9 * * *"  # Every day at 9:00 AM UTC
  class: "WarrantySchedulerJob"
  queue: default

# Weekly file cleanup on Sundays at 2 AM UTC
FileCleanup:
  cron: "0 2 * * 0"  # Every Sunday at 2:00 AM UTC
  class: "FileCleanupJob"
  queue: default

# Monthly product data refresh on 1st of each month at 1 AM UTC
ProductRefresh:
  cron: "0 1 1 * *"  # 1st of every month at 1:00 AM UTC
  class: "ProductRefreshJob"
  queue: default
