# Seeds for Warranty Vault API
# Run with: bin/rails db:seed

puts "🌱 Seeding database for Warranty Vault..."

# Clean existing data
puts "Cleaning existing data..."
GmailConnection.destroy_all
Notification.destroy_all
Invoice.destroy_all
User.destroy_all

# Create demo user
puts "Creating demo user..."
demo_user = User.create!(
  email: "demo@warrantyvault.com",
  password: "Demo@1234",
  first_name: "Demo",
  last_name: "User",
  role: :member,
  last_sign_in_at: Time.current,
  sign_in_count: 1
)

# Create additional test user
test_user = User.create!(
  email: "test@warrantyvault.com",
  password: "Test@1234",
  first_name: "Test",
  last_name: "User",
  role: :member
)

puts "✓ Users created"

# Sample invoice data
invoices_data = [
  {
    product_name: "MacBook Pro 14\"",
    brand: "Apple",
    seller: "Apple Store",
    amount: 1999.00,
    purchase_date: 3.months.ago,
    warranty_duration: 24,
    category: "Electronics"
  },
  {
    product_name: "Sony WH-1000XM5 Headphones",
    brand: "Sony",
    seller: "Amazon",
    amount: 349.99,
    purchase_date: 8.months.ago,
    warranty_duration: 12,
    category: "Electronics"
  },
  {
    product_name: "Samsung Family Hub Refrigerator",
    brand: "Samsung",
    seller: "Best Buy",
    amount: 2499.00,
    purchase_date: 6.months.ago,
    warranty_duration: 24,
    category: "Appliances"
  },
  {
    product_name: "Dyson V15 Detect Vacuum",
    brand: "Dyson",
    seller: "Dyson",
    amount: 749.99,
    purchase_date: 11.months.ago,
    warranty_duration: 12,
    category: "Appliances"
  },
  {
    product_name: "iPhone 15 Pro Max",
    brand: "Apple",
    seller: "Apple Store",
    amount: 1199.00,
    purchase_date: 2.weeks.ago,
    warranty_duration: 12,
    category: "Electronics"
  },
  {
    product_name: "LG OLED55C3PUA 55\" TV",
    brand: "LG",
    seller: "Best Buy",
    amount: 1299.99,
    purchase_date: 4.months.ago,
    warranty_duration: 12,
    category: "Electronics"
  },
  {
    product_name: "Breville Barista Express Espresso Machine",
    brand: "Breville",
    seller: "Williams Sonoma",
    amount: 699.95,
    purchase_date: 1.year.ago,
    warranty_duration: 12,
    category: "Appliances"
  },
  {
    product_name: "Herman Miller Aeron Chair",
    brand: "Herman Miller",
    seller: "Design Within Reach",
    amount: 1445.00,
    purchase_date: 5.months.ago,
    warranty_duration: 120,
    category: "Furniture"
  },
  {
    product_name: "Canon EOS R6 Mark II",
    brand: "Canon",
    seller: "B&H Photo",
    amount: 2499.00,
    purchase_date: 7.months.ago,
    warranty_duration: 12,
    category: "Electronics"
  },
  {
    product_name: "KitchenAid Stand Mixer",
    brand: "KitchenAid",
    seller: "Target",
    amount: 449.99,
    purchase_date: 2.years.ago,
    warranty_duration: 12,
    category: "Appliances"
  },
  {
    product_name: "iPad Pro 12.9\"",
    brand: "Apple",
    seller: "Apple Store",
    amount: 1099.00,
    purchase_date: 1.month.ago,
    warranty_duration: 12,
    category: "Electronics"
  },
  {
    product_name: "Bosch 800 Series Dishwasher",
    brand: "Bosch",
    seller: "Home Depot",
    amount: 1149.00,
    purchase_date: 9.months.ago,
    warranty_duration: 24,
    category: "Appliances"
  }
]

puts "Creating invoices for demo user..."
invoices_data.each do |data|
  invoice = demo_user.invoices.create!(data)

  # Create notifications for some invoices
  if invoice.warranty_status == "expiring_soon"
    Notification.create!(
      user: demo_user,
      title: "Warranty Expiring Soon",
      message: "Your warranty for #{invoice.product_name} expires in #{invoice.days_remaining} days.",
      notification_type: :warranty_expiring,
      action_url: "/invoices/#{invoice.id}",
      read: false
    )
  elsif invoice.warranty_status == "expired"
    Notification.create!(
      user: demo_user,
      title: "Warranty Expired",
      message: "Your warranty for #{invoice.product_name} has expired.",
      notification_type: :warranty_expired,
      action_url: "/invoices/#{invoice.id}",
      read: true
    )
  end
end

# Create some general notifications
Notification.create!(
  user: demo_user,
  title: "Welcome to Warranty Vault!",
  message: "Start by uploading your first receipt or connecting your Gmail account.",
  notification_type: :general,
  read: false
)

puts "Creating invoices for test user..."
test_invoices = [
  {
    product_name: "Dell XPS 15 Laptop",
    brand: "Dell",
    seller: "Dell",
    amount: 1799.00,
    purchase_date: 4.months.ago,
    warranty_duration: 24,
    category: "Electronics"
  },
  {
    product_name: "Sonos Arc Soundbar",
    brand: "Sonos",
    seller: "Amazon",
    amount: 899.00,
    purchase_date: 6.months.ago,
    warranty_duration: 12,
    category: "Electronics"
  }
]

test_invoices.each do |data|
  test_user.invoices.create!(data)
end

puts ""
puts "✅ Seeding complete!"
puts ""
puts "📊 Summary:"
puts "   - Users: #{User.count}"
puts "   - Invoices: #{Invoice.count}"
puts "   - Notifications: #{Notification.count}"
puts ""
puts "🔐 Demo Credentials:"
puts "   Email: demo@warrantyvault.com"
puts "   Password: Demo@1234"
puts ""
puts "🔐 Test Credentials:"
puts "   Email: test@warrantyvault.com"
puts "   Password: Test@1234"
