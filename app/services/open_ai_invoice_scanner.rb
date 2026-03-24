# frozen_string_literal: true

# AI-powered Invoice Scanning Service using OpenAI
# Extracts structured product and warranty data from invoice text/images
#
# Usage:
#   OpenAiInvoiceScanner.new(invoice).process
#   OpenAiInvoiceScanner.scan_text(raw_text)
class OpenAiInvoiceScanner
  class OpenAiError < StandardError; end
  class ConfigurationError < StandardError; end

  # OpenAI model configuration from Rails config
  MODEL = Rails.application.config.ai_services.openai_model
  TEMPERATURE = Rails.application.config.ai_services.openai_temperature
  MAX_TOKENS = Rails.application.config.ai_services.openai_max_tokens

  # Timeout for API requests (seconds)
  TIMEOUT = 30

  attr_reader :invoice, :client

  def initialize(invoice)
    @invoice = invoice
    @client = build_client
  end

  # Main entry point - process invoice file with AI
  def process
    raise OpenAiError, "No file attached" unless @invoice.file.attached?

    Rails.logger.info "[OpenAiInvoiceScanner] Starting AI processing for invoice #{@invoice.id}"

    # Extract text from file (OCR first if image/PDF)
    raw_text = extract_text_from_file

    return { success: false, error: "No text extracted from file" } if raw_text.blank?

    # Send to OpenAI for structured extraction
    extract_structured_data(raw_text)
  rescue => e
    Rails.logger.error "[OpenAiInvoiceScanner] Error: #{e.message}"
    Rails.logger.error "[OpenAiInvoiceScanner] #{e.class}: #{e.backtrace.first(5).join("\n")}"
    { success: false, error: e.message }
  end

  # Class method for scanning raw text directly
  def self.scan_text(raw_text)
    scanner = new(nil)
    scanner.extract_structured_data(raw_text)
  end

  # Class method for scanning with vision (image files)
  def self.scan_image(file_path, api_key: nil)
    scanner = new(nil, api_key: api_key)
    scanner.extract_from_image(file_path)
  end

  private

  # Build OpenAI client
  def build_client(api_key: nil)
    key = api_key || ENV.fetch("OPENAI_API_KEY", nil)
    raise ConfigurationError, "OpenAI API key not configured" unless key.present?

    OpenAI::Client.new(access_token: key, request_timeout: TIMEOUT)
  end

  # Extract text from uploaded file
  def extract_text_from_file
    case @invoice.file.content_type
    when "application/pdf"
      extract_text_from_pdf
    when "image/jpeg", "image/png", "image/jpg"
      extract_text_from_image
    when "text/plain"
      @invoice.file.blob.download
    else
      # Try to read as text
      @invoice.file.blob.download
    end
  end

  # Extract text from PDF using pdf-reader gem
  def extract_text_from_pdf
    require "pdf-reader"

    file_path = download_file
    text = ""

    PDF::Reader.new(file_path).pages.each do |page|
      text += page.text + "\n"
    end

    text
  rescue LoadError
    # Fallback: try to read as binary and extract strings
    File.read(file_path, mode: "rb").gsub(/[^\x20-\x7E\n]/, "")
  ensure
    FileUtils.rm_f(file_path) if file_path && File.exist?(file_path)
  end

  # Extract text from image using Google Vision or Tesseract
  def extract_text_from_image
    # Try Google Vision first (if configured)
    if google_vision_available?
      extract_with_google_vision
    else
      # Fallback: use OpenAI Vision API
      file_path = download_file
      extract_with_openai_vision(file_path)
    end
  end

  # Extract text using Google Cloud Vision
  def extract_with_google_vision
    require "google/cloud/vision"

    file_path = download_file
    vision = Google::Cloud::Vision.new(
      project_id: ENV.fetch("GOOGLE_PROJECT_ID", nil),
      credentials: ENV.fetch("GOOGLE_APPLICATION_CREDENTIALS", nil)
    )
    file_content = File.read(file_path)
    response = vision.document_text_detection(content: file_content, mime_type: @invoice.file.content_type)
    response.full_text_annotation&.text || ""
  ensure
    FileUtils.rm_f(file_path) if file_path && File.exist?(file_path)
  end

  # Extract text using OpenAI Vision API
  def extract_with_openai_vision(file_path)
    file_content = Base64.encode64(File.read(file_path))

    response = @client.chat(
      parameters: {
        model: MODEL,
        messages: [
          {
            role: "user",
            content: [
              {
                type: "text",
                text: "Extract all text from this invoice image. Return only the raw text content."
              },
              {
                type: "image_url",
                image_url: {
                  url: "data:#{@invoice.file.content_type};base64,#{file_content}"
                }
              }
            ]
          }
        ],
        max_tokens: MAX_TOKENS
      }
    )

    response.dig("choices", 0, "message", "content") || ""
  end

  # Extract structured data using OpenAI
  def extract_structured_data(raw_text)
    Rails.logger.info "[OpenAiInvoiceScanner] Sending text to OpenAI for structured extraction"
    response = @client.chat(
      parameters: {
        model: MODEL,
        messages: build_messages(raw_text),
        temperature: TEMPERATURE,
        max_tokens: MAX_TOKENS,
        response_format: { type: "json_object" }
      }
    )

    content = response.dig("choices", 0, "message", "content")
    parsed_data = JSON.parse(content)

    # Update invoice with extracted data
    update_invoice_with_extracted_data(parsed_data, raw_text)

    {
      success: true,
      data: parsed_data,
      raw_text: raw_text
    }
  rescue JSON::ParserError => e
    Rails.logger.error "[OpenAiInvoiceScanner] Failed to parse OpenAI response: #{e.message}"
    { success: false, error: "Failed to parse AI response: #{e.message}" }
  rescue StandardError => e
    Rails.logger.error "[OpenAiInvoiceScanner] OpenAI error: #{e.message}"
    { success: false, error: "AI service error: #{e.message}" }
  end

  # Build messages for OpenAI API
  def build_messages(raw_text)
    [
      {
        role: "system",
        content: SYSTEM_PROMPT
      },
      {
        role: "user",
        content: "Extract structured data from the following invoice text:\n\n#{raw_text}"
      }
    ]
  end

  # Update invoice record with extracted data
  def update_invoice_with_extracted_data(data, raw_text)
    return unless @invoice

    # Extract store information
    store_info = data["store_info"] || {}

    # Extract first item (primary product)
    item = data["items"]&.first || {}

    # Prepare comprehensive update data
    update_data = {
      # Basic product info
      product_name: item["product_name"],
      brand: item["brand"],
      model_number: item["model_number"],

      # Store information
      seller: store_info["name"],
      store_address: store_info["address"],
      store_phone: store_info["phone"],
      store_gstin: store_info["gstin"],
      invoice_number: store_info["invoice_number"],

      # Pricing information
      amount: item["total_amount"] || item["unit_price"],
      mrp: item["mrp"],
      discount: item["discount"],
      gst_percentage: item["gst_percentage"],
      gst_amount: item["gst_amount"],

      # Purchase details
      purchase_date: parse_date(item["purchase_date"] || store_info["invoice_date"]),
      invoice_date: parse_date(store_info["invoice_date"]),
      invoice_time: store_info["invoice_time"],

      # Product specifications
      color: item["color"],
      specifications: item["specifications"],
      part_number: item["part_number"],
      serial_number: item["serial_number"],
      category: item["category"],

      # Warranty and status
      warranty_duration: calculate_total_warranty_duration(data["warranty_details"]),
      ocr_data: data.merge(raw_text: raw_text).to_json,
      ocr_status: :completed,
      ocr_error_message: nil,
      confidence_score: item["confidence_score"]
    }

    # Update invoice with all extracted data
    @invoice.assign_attributes(update_data)
    @invoice.save!(validate: false)

    # Create comprehensive warranties from extracted data
    create_comprehensive_warranties(data) if data["warranty_details"].present?

    # Store additional information
    store_additional_info(data["additional_info"]) if data["additional_info"].present?

    # Schedule product image fetch
    schedule_product_image_fetch

    Rails.logger.info "[OpenAiInvoiceScanner] Enhanced invoice #{@invoice.id} with complete AI-extracted data"
  end

  # Schedule product image fetch job
  def schedule_product_image_fetch
    return unless @invoice.persisted?

    # Schedule image fetch to run after OCR completion
    # Product image fetching is now handled synchronously in InvoiceOcrJob
    Rails.logger.info "[OpenAiInvoiceScanner] Scheduled product image fetch for invoice #{@invoice.id}"
  end

  # Create comprehensive warranty records from extracted data
  def create_comprehensive_warranties(data)
    purchase_date = @invoice.purchase_date
    return unless purchase_date

    warranty_details = data["warranty_details"]
    return if warranty_details.blank?

    # Clear existing warranties for this invoice
    @invoice.product_warranties.destroy_all

    warranty_details.each_with_index do |warranty, index|
      # Calculate duration in months
      duration_months = warranty["duration_months"] || (warranty["duration_years"] * 12)

      # Calculate expiry date
      expiry_date = purchase_date + duration_months.months

      # Create warranty record
      ProductWarranty.create!(
        invoice: @invoice,
        component: warranty["component"],
        duration_months: duration_months,
        expires_at: expiry_date,
        description: warranty["description"],
        warranty_type: warranty["component"] == "product" ? "standard" : "extended"
      )

      Rails.logger.info "[OpenAiInvoiceScanner] Created #{warranty['component']} warranty: #{duration_months} months, expires #{expiry_date}"
    end
  end

  # Calculate total warranty duration from all warranties
  def calculate_total_warranty_duration(warranty_details)
    return nil unless warranty_details.present?

    # Find the longest warranty (usually the product warranty)
    product_warranty = warranty_details.find { |w| w["component"] == "product" }
    return nil unless product_warranty

    product_warranty["duration_months"] || (product_warranty["duration_years"] * 12)
  end

  # Store additional information
  def store_additional_info(additional_info)
    # Store in metadata or additional fields as needed
    metadata = {
      delivery_details: additional_info["delivery_details"],
      installation_details: additional_info["installation_details"],
      customer_service: additional_info["customer_service"],
      terms: additional_info["terms"]
    }.compact

    if metadata.any?
      @invoice.update_column(:metadata, metadata.to_json)
      Rails.logger.info "[OpenAiInvoiceScanner] Stored additional info: #{metadata.keys.join(', ')}"
    end
  end

  # Normalize component name to standard values
  def normalize_component(name)
    return "product" if name.blank?

    name = name.downcase.strip

    # Map common variations
    component_mapping = {
      "product" => %w[product products item unit main],
      "compressor" => %w[compressor compressors comp],
      "battery" => %w[battery batteries batt],
      "motor" => %w[motor motors engine engines],
      "display" => %w[display screen panel lcd led oled],
      "pump" => %w[pump pumps water pump circulation],
      "filter" => %w[filter filters air filter water]
    }

    component_mapping.each do |standard, variations|
      return standard if variations.any? { |v| name.include?(v) }
    end

    name.gsub(/[^a-z]/, "_")
  end

  # Parse date from various formats
  def parse_date(date_str)
    return nil unless date_str.present?

    # Try common formats
    formats = [ "%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y", "%B %d, %Y", "%d %B %Y", "%b %d, %Y" ]

    formats.each do |format|
      begin
        return Date.strptime(date_str.to_s, format)
      rescue ArgumentError
        next
      end
    end

    # Fallback to Date.parse
    Date.parse(date_str.to_s) rescue nil
  end

  # Download file to temp location
  def download_file
    file = Tempfile.new([ "invoice_", ".#{@invoice.file.filename.extension}" ])
    file.binmode
    file.write(@invoice.file.blob.download)
    file.close
    file.path
  end

  # Check if Google Vision is available
  def google_vision_available?
    ENV["GOOGLE_PROJECT_ID"].present? && ENV["GOOGLE_APPLICATION_CREDENTIALS"].present?
  end

  # System prompt for OpenAI - defines the extraction schema
  SYSTEM_PROMPT = <<~PROMPT
    You are an expert invoice data extraction AI. Extract ALL product and warranty details from this invoice.

    CRITICAL: Extract EVERY piece of information visible in the invoice including:

    1. STORE INFORMATION:
    - Store name, address, phone, GSTIN/TAX ID
    - Invoice number, date, time

    2. PRODUCT DETAILS (for each product):
    - Complete product name (exact as shown)
    - Brand/Manufacturer
    - Model number, part number, serial number
    - Color, size, specifications
    - Category (electronics/appliances/furniture/tools/sports/automotive/clothing/general)

    3. PRICING INFORMATION:
    - MRP/List price
    - Discount amount
    - Net amount/unit price
    - GST/VAT tax amounts and percentages
    - Total amount paid

    4. WARRANTY INFORMATION:
    - Standard warranty duration (in years/months)
    - Extended warranty details (compressor, battery, motor, etc.)
    - Total warranty coverage period
    - Warranty terms and conditions

    5. PURCHASE DETAILS:
    - Purchase date (DD/MM/YYYY format)
    - Payment method
    - Delivery/installation details

    WARRANTY PROCESSING:
    - Convert ALL warranty periods to months (1 year = 12 months)
    - Create separate warranty entries for each component (product, compressor, battery, etc.)
    - Calculate expiry date: purchase_date + warranty_duration_months
    - For multi-year warranties, break down by component

    CONFIDENCE SCORING:
    - 1.0 = Exact match (text clearly visible)
    - 0.8 = High confidence (slightly unclear but readable)
    - 0.6 = Medium confidence (partially visible/estimated)
    - 0.4 = Low confidence (very unclear/partial)
    - 0.2 = Very low confidence (guessed/estimated)

    Return ONLY valid JSON with this structure:

    {
      "store_info": {
        "name": "string",
        "address": "string",
        "phone": "string",
        "gstin": "string",
        "invoice_number": "string",
        "invoice_date": "YYYY-MM-DD",
        "invoice_time": "HH:MM:SS"
      },
      "items": [
        {
          "product_name": "string (required, exact as shown)",
          "brand": "string",
          "model_number": "string",
          "part_number": "string",
          "serial_number": "string",
          "color": "string",
          "specifications": "string",
          "category": "electronics|appliances|furniture|tools|sports|automotive|clothing|general",
          "mrp": number,
          "discount": number,
          "unit_price": number,
          "quantity": number,
          "gst_percentage": number,
          "gst_amount": number,
          "total_amount": number,
          "purchase_date": "YYYY-MM-DD",
          "confidence_score": 0.0-1.0
        }
      ],
      "warranty_details": [
        {
          "component": "string (product, compressor, battery, motor, display, etc.)",
          "duration_years": number,
          "duration_months": number,
          "description": "string (exact warranty terms)",
          "expiry_date": "YYYY-MM-DD"
        }
      ],
      "payment_info": {
        "payment_method": "string",
        "total_amount": number,
        "amount_paid": number,
        "balance_due": number
      },
      "additional_info": {
        "delivery_details": "string",
        "installation_details": "string",
        "customer_service": "string",
        "terms": "string"
      }
    }

    EXTRACTION RULES:
    - Return ONLY valid JSON. No explanations, no markdown, no text outside JSON.
    - All dates in YYYY-MM-DD format.
    - Use null for missing fields (not empty strings).
    - Extract MULTIPLE products if present.
    - Extract ALL warranty information separately.
    - Include pricing details for each product.
    - Preserve exact product names and model numbers.
    - Extract GST/TAX details if available.
    - High confidence for clearly visible text.
  PROMPT
end
