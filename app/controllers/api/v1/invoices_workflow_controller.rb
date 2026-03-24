# Controller for the complete invoice processing workflow
# Handles upload -> OCR -> product lookup -> warranty calculation -> storage
class Api::V1::InvoicesWorkflowController < ApplicationController
  before_action :authenticate_user!
  before_action :set_invoice, only: [ :show, :update, :destroy ]

  # POST /api/v1/invoices_workflow/upload_and_process
  # Complete workflow: Upload -> OCR -> Enrichment -> Warranty calculation
  def upload_and_process
    return render json: { error: "No file provided" }, status: :bad_request unless params[:file]

    begin
      # Step 1: Create invoice with file
      invoice = create_invoice_with_file
      binding.pry
      # Step 2: Queue OCR processing
      OcrProcessingJob.perform_later(invoice.id)

      # Step 3: Queue product enrichment (will run after OCR completes)
      ProductEnrichmentJob.set(wait: 30.seconds).perform_later(invoice.id)

      render json: {
        success: true,
        message: "Invoice uploaded and processing started",
        invoice_id: invoice.id,
        status: "processing",
        next_steps: [
          "OCR scanning in progress",
          "Product details fetching",
          "Warranty calculation",
          "Dashboard ready"
        ]
      }, status: :accepted

    rescue => e
      Rails.logger.error "[InvoicesWorkflow] Upload failed: #{e.message}"
      render json: {
        success: false,
        error: "Failed to upload invoice: #{e.message}"
      }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/invoices_workflow/manual_entry
  # Manual product entry workflow
  def manual_entry
    invoice_params = manual_entry_params

    begin
      # Step 1: Create invoice with manual data
      invoice = current_user.invoices.create!(invoice_params)

      # Step 2: Queue product enrichment
      ProductEnrichmentJob.perform_later(invoice.id)

      # Step 3: Create warranties if provided
      create_component_warranties(invoice) if params[:warranties].present?

      render json: {
        success: true,
        message: "Product added successfully",
        invoice: invoice_serializer(invoice),
        status: "completed"
      }, status: :created

    rescue => e
      Rails.logger.error "[InvoicesWorkflow] Manual entry failed: #{e.message}"
      render json: {
        success: false,
        error: "Failed to add product: #{e.message}"
      }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/invoices_workflow/status
  # Check processing status of an invoice
  def status
    invoice_id = params[:invoice_id]
    return render json: { error: "Invoice ID required" }, status: :bad_request unless invoice_id

    invoice = current_user.invoices.find_by(id: invoice_id)
    return render json: { error: "Invoice not found" }, status: :not_found unless invoice

    # Calculate estimated processing time
    created_at = invoice.created_at
    time_elapsed = Time.current - created_at
    estimated_total = 10 # seconds
    progress = calculate_progress(invoice)

    status_data = {
      invoice_id: invoice.id,
      ocr_status: invoice.ocr_status,
      product_enriched: invoice.product_enriched?,
      warranty_status: invoice.warranty_status,
      has_file: invoice.file.attached?,
      processing_complete: invoice.processing_complete?,
      errors: invoice.ocr_error_message,
      progress: progress,
      time_elapsed: time_elapsed.round(1),
      estimated_total: estimated_total,
      estimated_remaining: [ estimated_total - time_elapsed, 0 ].max.round(1)
    }

    render json: {
      success: true,
      status: status_data,
      invoice: invoice_serializer(invoice)
    }
  end

  # GET /api/v1/invoices_workflow/processing_time
  # Get estimated processing time
  def processing_time
    render json: {
      success: true,
      data: {
        estimated_seconds: 10,
        stages: {
          ocr: "3-8 seconds",
          warranty_calculation: "1-2 seconds",
          product_enrichment: "5-15 seconds (runs in background)"
        },
        tips: [
          "Keep invoice files under 5MB for faster processing",
          "PDF files are faster than images",
          "Clear text invoices process faster than scanned images"
        ]
      }
    }
  end

  private

  # Calculate processing progress (0-100)
  def calculate_progress(invoice)
    return 100 if invoice.processing_complete?
    return 0 if invoice.ocr_status == "pending"

    progress = 0

    # OCR complete: 40%
    progress += 40 if invoice.ocr_status == "completed"

    # Product enriched: +40%
    progress += 40 if invoice.product_enriched?

    # Has warranties: +20%
    progress += 20 if invoice.product_warranties.any?

    progress
  end

  # POST /api/v1/invoices_workflow/retry_ocr
  # Retry OCR processing if it failed
  def retry_ocr
    invoice_id = params[:invoice_id]
    return render json: { error: "Invoice ID required" }, status: :bad_request unless invoice_id

    invoice = current_user.invoices.find_by(id: invoice_id)
    return render json: { error: "Invoice not found" }, status: :not_found unless invoice

    if invoice.ocr_status == "failed"
      invoice.update_columns(ocr_status: :pending, ocr_error_message: nil)
      OcrProcessingJob.perform_later(invoice.id)

      render json: {
        success: true,
        message: "OCR processing restarted"
      }
    else
      render json: {
        success: false,
        error: "OCR can only be retried for failed invoices"
      }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/invoices_workflow/refresh_product
  # Refresh product lookup data
  def refresh_product
    invoice_id = params[:invoice_id]
    return render json: { error: "Invoice ID required" }, status: :bad_request unless invoice_id

    invoice = current_user.invoices.find_by(id: invoice_id)
    return render json: { error: "Invoice not found" }, status: :not_found unless invoice

    ProductEnrichmentJob.perform_later(invoice.id)

    render json: {
      success: true,
      message: "Product data refresh started"
    }
  end

  private

  def create_invoice_with_file
    invoice = current_user.invoices.new(
      seller: params[:seller],
      category: params[:category],
      ocr_status: :pending
    )

    # Attach file
    invoice.file.attach(params[:file])

    # Save without validations (OCR will populate required fields)
    invoice.save!(validate: false)

    invoice
  end

  def create_component_warranties(invoice)
    warranties_data = params[:warranties]

    warranties_data.each do |warranty_data|
      invoice.product_warranties.create!(
        component_name: warranty_data[:component_name],
        warranty_months: warranty_data[:warranty_months],
        expires_at: calculate_expiry_date(invoice.purchase_date, warranty_data[:warranty_months])
      )
    end
  end

  def calculate_expiry_date(purchase_date, duration_months)
    return nil unless purchase_date && duration_months

    purchase_date + duration_months.to_i.months
  end

  def manual_entry_params
    params.permit(
      :product_name,
      :brand,
      :model_number,
      :seller,
      :purchase_date,
      :amount,
      :warranty_duration,
      :category
    )
  end

  def set_invoice
    @invoice = current_user.invoices.find_by(id: params[:id])
  end

  def invoice_serializer(invoice)
    {
      id: invoice.id,
      product_name: invoice.product_name,
      brand: invoice.brand,
      model_number: invoice.model_number,
      seller: invoice.seller,
      purchase_date: invoice.purchase_date,
      amount: invoice.amount,
      warranty_duration: invoice.warranty_duration,
      category: invoice.category,
      warranty_status: invoice.warranty_status,
      expires_at: invoice.expires_at,
      days_remaining: invoice.days_remaining,
      ocr_status: invoice.ocr_status,
      product_enriched: invoice.product_enriched?,
      product_image_url: invoice.product_image_url,
      product_description: invoice.product_description,
      file_url: invoice.file.attached? ? Rails.application.routes.url_helpers.rails_blob_url(invoice.file, only_path: true) : nil,
      created_at: invoice.created_at,
      updated_at: invoice.updated_at,
      warranties: invoice.product_warranties.map do |warranty|
        {
          id: warranty.id,
          component_name: warranty.component_name,
          warranty_months: warranty.warranty_months,
          expires_at: warranty.expires_at,
          days_remaining: warranty.days_remaining,
          active: warranty.active?,
          expired: warranty.expired?,
          expiring_soon: warranty.expiring_soon?
        }
      end
    }
  end
end
