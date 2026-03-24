# frozen_string_literal: true

# Gemini AI Invoice Scanner - Enhanced with strict extraction rules
#
# Improvements:
# 1. STRICT warranty extraction - ALWAYS extract if present
# 2. Multiple warranty detection - captures all component warranties
# 3. Model number fallback - uses product_name if model_number missing
# 4. Enhanced prompt with explicit rules and examples
# 5. Post-processing validation with regex fallbacks
# 6. Comprehensive logging for debugging
#
# Usage:
#   GeminiInvoiceScanner.new(invoice).process
class GeminiInvoiceScanner
  class GeminiError < StandardError; end
  class ConfigurationError < StandardError; end

  # Gemini model configuration from Rails config
  MODEL = Rails.application.config.ai_services.gemini_model
  TEMPERATURE = Rails.application.config.ai_services.gemini_temperature
  MAX_TOKENS = Rails.application.config.ai_services.gemini_max_tokens
  TIMEOUT = 30

  attr_reader :invoice, :client

  def initialize(invoice)
    @invoice = invoice
    @client = build_client
  end

  def process
    return { success: false, error: "No file attached" } unless @invoice.file.attached?

    Rails.logger.info "[GeminiInvoiceScanner] Starting processing for invoice #{@invoice.id}"

    # Extract text with timeout protection
    raw_text = extract_text_with_timeout
    return { success: false, error: "No text extracted from file" } if raw_text.blank?

    Rails.logger.info "[GeminiInvoiceScanner] Extracted #{raw_text.length} characters from invoice #{@invoice.id}"
    Rails.logger.info "[GeminiInvoiceScanner] OCR TEXT START"
    Rails.logger.info raw_text
    Rails.logger.info "[GeminiInvoiceScanner] OCR TEXT END"

    # Send to Gemini with ENHANCED structured prompt
    result = extract_structured_data_with_gemini(raw_text)

    # Post-processing validation and fallbacks
    if result[:success]
      result = post_process_and_validate(result, raw_text)
      
      # Update invoice with extracted data
      update_invoice_with_extracted_data(result[:data], raw_text)
      Rails.logger.info "[GeminiInvoiceScanner] Successfully processed invoice #{@invoice.id}"
      Rails.logger.info "[GeminiInvoiceScanner] FINAL EXTRACTED DATA:"
      Rails.logger.info "  - Product: #{result[:data]['product_name']}"
      Rails.logger.info "  - Brand: #{result[:data]['brand']}"
      Rails.logger.info "  - Model: #{result[:data]['model_number']}"
      Rails.logger.info "  - Warranties: #{result[:data]['warranty_details']&.inspect || 'none'}"
    else
      Rails.logger.error "[GeminiInvoiceScanner] Failed to process invoice #{@invoice.id}: #{result[:error]}"
    end

    result
  rescue => e
    Rails.logger.error "[GeminiInvoiceScanner] Error processing invoice #{@invoice.id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    { success: false, error: e.message }
  end

  private

  # Build Gemini client
  def build_client
    # google-genai is manually loaded in config/initializers/google_genai.rb 
    # to avoid a Zeitwerk naming conflict in the gem's own loader.

    api_key = ENV.fetch("GEMINI_API_KEY", nil)
    raise ConfigurationError, "GEMINI_API_KEY not configured" unless api_key

    # Set the API key in the environment for the gem to pick up
    ENV["GOOGLE_API_KEY"] = api_key

    client = Google::Genai::Client.new

    Rails.logger.info "[GeminiInvoiceScanner] Gemini client initialized with model: #{MODEL}"
    client
  rescue LoadError => e
    raise ConfigurationError, "google-genai gem not found: #{e.message}"
  rescue => e
    raise ConfigurationError, "Failed to initialize Gemini client: #{e.message}"
  end

  # Extract text with timeout protection
  def extract_text_with_timeout
    Timeout.timeout(TIMEOUT) do
      if @invoice.file.content_type.include?("pdf")
        extract_text_from_pdf
      elsif @invoice.file.content_type.include?("image")
        extract_text_from_image
      else
        extract_text_from_document
      end
    end
  rescue Timeout::Error
    Rails.logger.error "[GeminiInvoiceScanner] Text extraction timeout for invoice #{@invoice.id}"
    nil
  end

  # Extract text from PDF
  def extract_text_from_pdf
    require "pdf/reader"
    
    file_path = download_file
    reader = PDF::Reader.new(file_path)
    text = reader.pages.map(&:text).join("\n")
    text.strip
  rescue LoadError
    file_path = download_file
    File.read(file_path, mode: "rb").gsub(/[^\x20-\x7E\n]/, "")
  ensure
    FileUtils.rm_f(file_path) if file_path && File.exist?(file_path)
  end

  # Extract text from image using Google Vision
  def extract_text_from_image
    require "google/cloud/vision"

    file_path = download_file
    vision = Google::Cloud::Vision.new(
      project_id: ENV.fetch("GOOGLE_PROJECT_ID", "warranty-vault"),
      credentials: ENV.fetch("GOOGLE_APPLICATION_CREDENTIALS", nil)
    )

    image = vision.image file_path
    response = image.text
    response.text.strip
  ensure
    FileUtils.rm_f(file_path) if file_path && File.exist?(file_path)
  end

  # Extract text from document
  def extract_text_from_document
    file_path = download_file
    File.read(file_path, encoding: "UTF-8").strip
  ensure
    FileUtils.rm_f(file_path) if file_path && File.exist?(file_path)
  end

  # Download file to temp location
  def download_file
    file_path = Rails.root.join("tmp", "invoice_#{@invoice.id}_#{SecureRandom.uuid}")
    File.open(file_path, "wb") do |file|
      file.write(@invoice.file.download)
    end
    file_path
  end

  # Extract structured data with Gemini - ENHANCED PROMPT
  def extract_structured_data_with_gemini(raw_text)
    prompt = build_enhanced_gemini_prompt(raw_text)
    
    Rails.logger.info "[GeminiInvoiceScanner] Sending to Gemini with enhanced prompt"
    
    result = make_gemini_request(prompt)
    
    if result[:success]
      parsed_data = parse_gemini_response(result[:response_text])
      
      if parsed_data[:success]
        # Log AI response for debugging
        Rails.logger.info "[GeminiInvoiceScanner] AI RESPONSE:"
        Rails.logger.info result[:response_text]
        Rails.logger.info "[GeminiInvoiceScanner] PARSED DATA:"
        Rails.logger.info parsed_data[:data].inspect
      end
      
      parsed_data
    else
      result
    end
  end

  # Make request to Gemini with timeout
  def make_gemini_request(prompt)
    Timeout.timeout(TIMEOUT) do
      response = @client.models.generate_content(
        model: MODEL,
        contents: [prompt],
        config: {
          temperature: TEMPERATURE,
          maxOutputTokens: MAX_TOKENS,
          responseMimeType: "application/json"
        }
      )

      response_text = response.text

      if response_text.blank?
        Rails.logger.warn "[GeminiInvoiceScanner] Empty response from Gemini"
        return { success: false, error: "Empty response from Gemini" }
      end

      { success: true, response_text: response_text }
    end
  rescue Timeout::Error
    Rails.logger.error "[GeminiInvoiceScanner] Gemini API timeout"
    { success: false, error: "Gemini API timeout after #{TIMEOUT}s" }
  rescue => e
    Rails.logger.error "[GeminiInvoiceScanner] Gemini API error: #{e.message}"
    { success: false, error: "Gemini API error: #{e.message}" }
  end

  # Build ENHANCED Gemini prompt with strict extraction rules
  def build_enhanced_gemini_prompt(raw_text)
    <<~PROMPT
      You are an expert invoice data extraction system with STRICT extraction rules.

      Your task is to extract structured data from invoice text with MAXIMUM ACCURACY.

      =====================================
      CRITICAL EXTRACTION RULES (MUST FOLLOW):
      =====================================

      1. WARRANTY EXTRACTION - HIGHEST PRIORITY:
         - ALWAYS extract warranty information if ANY warranty text is present
         - Detect ALL warranty mentions (product warranty + component warranties)
         - Common patterns to detect:
           * "1 year warranty" → duration_months: 12
           * "2 years warranty" → duration_months: 24
           * "12 months warranty" → duration_months: 12
           * "240 months warranty" → duration_months: 240
           * "1 year on compressor" → component: "compressor", duration_months: 12
           * "5 years on motor" → component: "motor", duration_months: 60
           * "10 years on parts" → component: "parts", duration_months: 120
           * "lifetime warranty" → duration_months: 9999 (special case)
         - If warranty exists but duration unclear → use best estimate from context
         - If multiple warranties exist → capture ALL of them separately
         - Component names: use exact text from invoice (compressor, motor, battery, etc.)
         - If no specific component mentioned → use "product" as default

      2. MODEL NUMBER - NEVER BLANK:
         - Extract model_number from invoice
         - If model_number NOT found → use product_name as model_number
         - If product_name also missing → use "UNKNOWN-MODEL"
         - Model number is REQUIRED - never return null/blank

      3. PRODUCT NAME:
         - Extract the main product name
         - Include brand + model if present (e.g., "Samsung 55\" QLED TV")
         - Be specific - not just "TV" but "55 inch QLED Smart TV"

      4. BRAND:
         - Extract manufacturer brand name
         - Common brands: Samsung, LG, Sony, Whirlpool, Haier, etc.
         - If brand not explicitly mentioned → infer from product name

      5. PURCHASE DATE:
         - Extract purchase/invoice date
         - Format: YYYY-MM-DD
         - If date unclear → use invoice date

      6. SELLER:
         - Extract retailer/seller name
         - Include store name and location if available

      7. TOTAL AMOUNT:
         - Extract total paid amount (numeric only, no currency symbols)
         - Include tax if itemized

      =====================================
      OUTPUT FORMAT (STRICT JSON):
      =====================================

      {
        "product_name": "Full product name with specifications",
        "brand": "Brand name",
        "model_number": "Model number OR product_name if model missing",
        "seller": "Seller/retailer name",
        "category": "Electronics|Appliances|Furniture|Tools|Other",
        "description": "Short description of the product",
        "specifications": "Technical specifications if available",
        "purchase_date": "YYYY-MM-DD",
        "total_amount": 1234.56,
        "warranty_details": [
          {
            "component": "product",
            "duration_months": 12
          }
        ]
      }

      =====================================
      EXAMPLES:
      =====================================

      Example 1 - Single Warranty:
      Input: "Samsung 55\" QLED TV Model QA55Q60BA purchased on 2024-01-15 from Best Buy for $899. Comes with 1 year manufacturer warranty."
      Output: {
        "product_name": "Samsung 55 inch QLED TV",
        "brand": "Samsung",
        "model_number": "QA55Q60BA",
        "seller": "Best Buy",
        "purchase_date": "2024-01-15",
        "total_amount": 899.00,
        "warranty_details": [
          {"component": "product", "duration_months": 12}
        ]
      }

      Example 2 - Multiple Warranties:
      Input: "LG Refrigerator Model GL-B281 purchased on 2024-02-20 from Croma for ₹25,000. 1 year comprehensive warranty + 10 years compressor warranty."
      Output: {
        "product_name": "LG Refrigerator",
        "brand": "LG",
        "model_number": "GL-B281",
        "seller": "Croma",
        "purchase_date": "2024-02-20",
        "total_amount": 25000.00,
        "warranty_details": [
          {"component": "product", "duration_months": 12},
          {"component": "compressor", "duration_months": 120}
        ]
      }

      Example 3 - No Model Number (use product_name):
      Input: "Sony Headphones bought on 2024-03-10 from Amazon for $150. 6 months warranty."
      Output: {
        "product_name": "Sony Headphones",
        "brand": "Sony",
        "model_number": "Sony Headphones",
        "seller": "Amazon",
        "purchase_date": "2024-03-10",
        "total_amount": 150.00,
        "warranty_details": [
          {"component": "product", "duration_months": 6}
        ]
      }

      =====================================
      INVOICE TEXT TO PROCESS:
      =====================================

      #{raw_text}

      =====================================
      REMINDER - CRITICAL RULES:
      =====================================
      - warranty_details: MUST extract ALL warranties (minimum 1 if any warranty mentioned)
      - model_number: NEVER blank - use product_name if model not found
      - Output ONLY valid JSON - no explanations
      - Use null for truly missing fields (except model_number)
    PROMPT
  end

  # Parse Gemini response
  def parse_gemini_response(response_text)
    return { success: false, error: "Empty response from Gemini" } if response_text.blank?

    # Clean response - remove markdown code blocks if present
    clean_response = response_text.gsub(/```json\s*/, "").gsub(/```\s*/, "").strip
    
    # Parse JSON
    data = JSON.parse(clean_response)
    
    # Validate required fields
    validation_result = validate_extracted_data(data)
    
    if validation_result[:success]
      { success: true, data: data }
    else
      { success: false, error: validation_result[:error], data: data }
    end
  rescue JSON::ParserError => e
    Rails.logger.error "[GeminiInvoiceScanner] JSON parse error: #{e.message}"
    Rails.logger.error "[GeminiInvoiceScanner] Raw response: #{response_text}"
    { success: false, error: "Invalid JSON response: #{e.message}" }
  rescue => e
    Rails.logger.error "[GeminiInvoiceScanner] Parse error: #{e.message}"
    { success: false, error: "Parse error: #{e.message}" }
  end

  # Validate extracted data
  def validate_extracted_data(data)
    errors = []
    
    # Check warranty_details
    if data["warranty_details"].blank? || !data["warranty_details"].is_a?(Array)
      errors << "warranty_details must be a non-empty array"
    elsif data["warranty_details"].any? { |w| !w.is_a?(Hash) }
      errors << "warranty_details must contain hash objects"
    end
    
    # Check model_number (critical - never blank)
    if data["model_number"].blank?
      errors << "model_number cannot be blank"
    end
    
    # Check product_name
    if data["product_name"].blank?
      errors << "product_name is required"
    end
    
    if errors.any?
      Rails.logger.warn "[GeminiInvoiceScanner] Validation errors: #{errors.join(', ')}"
      { success: false, error: errors.join(', ') }
    else
      { success: true }
    end
  end

  # Post-process and validate extracted data with fallbacks
  def post_process_and_validate(result, raw_text)
    data = result[:data]
    
    Rails.logger.info "[GeminiInvoiceScanner] Starting post-processing validation"
    
    # FALLBACK 1: Model number from product_name
    if data["model_number"].blank? && data["product_name"].present?
      data["model_number"] = data["product_name"]
      Rails.logger.info "[GeminiInvoiceScanner] Fallback: Set model_number = product_name"
    end
    
    # FALLBACK 2: Model number default
    if data["model_number"].blank?
      data["model_number"] = "UNKNOWN-MODEL"
      Rails.logger.info "[GeminiInvoiceScanner] Fallback: Set model_number to UNKNOWN-MODEL"
    end
    
    # FALLBACK 3: Warranty extraction with regex if AI failed
    if data["warranty_details"].blank? || data["warranty_details"].empty?
      Rails.logger.info "[GeminiInvoiceScanner] No warranties from AI, trying regex fallback"
      regex_warranties = extract_warranties_with_regex(raw_text)
      
      if regex_warranties.any?
        data["warranty_details"] = regex_warranties
        Rails.logger.info "[GeminiInvoiceScanner] Regex fallback extracted #{regex_warranties.count} warranties"
      end
    end
    
    # FALLBACK 4: Ensure at least one warranty if mentioned in text
    if (data["warranty_details"].blank? || data["warranty_details"].empty?) && raw_text.match?(/warranty|guarantee|yr\s+warranty|year\s+warranty/i)
      Rails.logger.info "[GeminiInvoiceScanner] Warranty mentioned but not extracted, adding default"
      data["warranty_details"] = [{ "component" => "product", "duration_months" => 12 }]
    end
    
    # Validate final data
    validation = validate_extracted_data(data)
    
    result[:data] = data
    result[:post_processed] = true
    result[:validation] = validation
    
    Rails.logger.info "[GeminiInvoiceScanner] Post-processing complete"
    Rails.logger.info "[GeminiInvoiceScanner] Final data: #{data.inspect}"
    
    result
  end

  # Extract warranties using regex patterns (fallback when AI fails)
  def extract_warranties_with_regex(text)
    warranties = []
    
    # Pattern 1: "X year(s) warranty" or "X months warranty"
    text.scan(/(\d+)\s*(year|yr|years|month|months)\s*(?:warranty|guarantee)/i) do |match|
      value = match[0].to_i
      unit = match[1].downcase
      duration = unit.start_with?('y') ? value * 12 : value
      warranties << { "component" => "product", "duration_months" => duration }
    end
    
    # Pattern 2: "X year(s) on [component]"
    text.scan(/(\d+)\s*(year|yr|years|month|months)\s*(?:warranty|guarantee)?\s*(?:on|for)\s+(\w+)/i) do |match|
      value = match[0].to_i
      unit = match[1].downcase
      component = match[2].downcase
      duration = unit.start_with?('y') ? value * 12 : value
      warranties << { "component" => component, "duration_months" => duration }
    end
    
    # Pattern 3: "X year(s) [component] warranty"
    text.scan(/(\d+)\s*(year|yr|years|month|months)\s+(\w+)\s*warranty/i) do |match|
      value = match[0].to_i
      unit = match[1].downcase
      component = match[2].downcase
      duration = unit.start_with?('y') ? value * 12 : value
      warranties << { "component" => component, "duration_months" => duration }
    end
    
    # Pattern 4: "compressor warranty - X years"
    text.scan(/(\w+)\s*warranty\s*[-:]\s*(\d+)\s*(year|yr|years|month|months)/i) do |match|
      component = match[0].downcase
      value = match[1].to_i
      unit = match[2].downcase
      duration = unit.start_with?('y') ? value * 12 : value
      warranties << { "component" => component, "duration_months" => duration }
    end
    
    # Remove duplicates and ensure at least one warranty
    warranties = warranties.uniq { |w| [w["component"], w["duration_months"]] }
    
    # If no specific component warranties but general warranty mentioned, add product warranty
    if warranties.empty? && text.match?(/warranty|guarantee/i)
      warranties << { "component" => "product", "duration_months" => 12 }
    end
    
    warranties
  end

  # Update invoice with extracted data
  def update_invoice_with_extracted_data(data, raw_text)
    # Calculate main warranty duration (for the product itself)
    product_warranty = data["warranty_details"]&.find { |w| w["component"] == "product" }
    warranty_months = product_warranty ? product_warranty["duration_months"] : nil

    update_data = {
      product_name: data["product_name"],
      brand: data["brand"],
      model_number: data["model_number"],
      seller: data["seller"],
      purchase_date: parse_date(data["purchase_date"]),
      amount: data["total_amount"],
      category: data["category"],
      description: data["description"],
      specifications: data["specifications"],
      warranty_duration: warranty_months,
      ocr_status: :completed,
      ocr_data: data.merge(raw_text: raw_text).to_json
    }

    # Validate purchase_date
    if update_data[:purchase_date].nil? || update_data[:purchase_date] > Date.current
      Rails.logger.warn "[GeminiInvoiceScanner] Invalid purchase date: #{update_data[:purchase_date]}, using current date"
      update_data[:purchase_date] = Date.current
      update_data[:ocr_error_message] = "Invalid purchase date, set to current date"
    end

    # Update invoice
    @invoice.assign_attributes(update_data)
    @invoice.save!(validate: false)

    # Create warranty records
    create_warranty_records(data["warranty_details"]) if data["warranty_details"].present?
    
    # Schedule reminder jobs
    schedule_reminder_jobs
    
    # Schedule product image fetch
    schedule_product_image_fetch

    Rails.logger.info "[GeminiInvoiceScanner] Updated invoice #{@invoice.id} with extracted data"
  end

  # Create warranty records from extracted data
  def create_warranty_records(warranty_details)
    return unless @invoice.purchase_date

    # Clear existing warranties
    @invoice.product_warranties.destroy_all

    warranty_details.each do |warranty|
      next unless warranty.is_a?(Hash)
      
      component = warranty["component"] || "product"
      duration_months = warranty["duration_months"] || 0
      next if duration_months.zero?

      # Calculate expiry date
      expires_at = @invoice.purchase_date + duration_months.months
      
      # Validate expiry date
      if expires_at.year < 2020 || expires_at.year > Date.current.year + 50
        Rails.logger.warn "[GeminiInvoiceScanner] Invalid expiry year #{expires_at.year} for #{component} warranty"
        next
      end

      ProductWarranty.create!(
        invoice: @invoice,
        component_name: component,
        warranty_months: duration_months,
        expires_at: expires_at
      )
      
      Rails.logger.info "[GeminiInvoiceScanner] Created #{component} warranty: #{duration_months} months, expires #{expires_at}"
    end
  end

  # Schedule reminder jobs
  def schedule_reminder_jobs
    WarrantyReminderService.schedule_for_invoice(@invoice)
  end

  # Schedule product image fetch
  def schedule_product_image_fetch
    # Product image fetching is now handled synchronously in InvoiceOcrJob
  end

  # Parse date from various formats
  def parse_date(date_str)
    return nil unless date_str.present?

    formats = [
      "%Y-%m-%d", "%d-%m-%Y", "%m-%d-%Y",
      "%d/%m/%Y", "%m/%d/%Y", "%Y/%m/%d",
      "%B %d, %Y", "%d %B %Y", "%b %d, %Y", "%d %b %Y",
      "%d %b %y", "%d-%b-%y"
    ]

    original_str = date_str.to_s.strip
    
    formats.each do |format|
      begin
        parsed_date = Date.strptime(original_str, format)
        return parsed_date if parsed_date.year >= 2020 && parsed_date.year <= Date.current.year + 1
      rescue ArgumentError
        next
      end
    end

    begin
      parsed_date = Date.parse(original_str)
      return parsed_date if parsed_date.year >= 2020 && parsed_date.year <= Date.current.year + 1
    rescue ArgumentError
      Rails.logger.warn "[GeminiInvoiceScanner] Failed to parse date: #{original_str}"
    end
    
    nil
  end
end
