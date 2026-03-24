module Api
  module V1
    class InvoicesController < ApplicationController
      before_action :set_invoice, only: [ :show, :update, :destroy, :download, :preview, :retry_ocr, :ocr_status ]

      # GET /api/v1/invoices
      def index
        invoices = current_user.invoices
                               .includes(file_attachment: :blob)
                               .order(purchase_date: :desc)

        invoices = invoices.search(params[:q]) if params[:q].present?
        invoices = invoices.where(warranty_status: params[:status]) if params[:status].present?
        invoices = invoices.where(category: params[:category]) if params[:category].present?
        paginated_invoices, pagination = paginate(invoices)

        render json: {
          invoices: paginated_invoices.map { |invoice| invoice_data(invoice, include_warranties: true) },
          pagination: pagination
        }
      end

      # GET /api/v1/invoices/:id
      def show
        render json: { invoice: invoice_data(@invoice, include_warranties: true) }
      end

      # POST /api/v1/invoices
      def create
        @invoice = current_user.invoices.new(invoice_params)
        # Handle file upload
        if params[:file].present?
          @invoice.original_filename = params[:file].original_filename
          @invoice.file.attach(params[:file])

          # Set a temporary product name if not provided
          @invoice.product_name ||= params[:file].original_filename.to_s.sub(/\.[^.]+\z/, "").humanize
        end

        # Save without validating required fields (OCR will populate them later)
        # We only validate file attachment at this stage
        @invoice.ocr_status = :pending

        if @invoice.save(validate: !@invoice.file.attached?)
          # Trigger OCR processing in background (uses Google Vision)
          InvoiceOcrJob.perform_later(@invoice.id) if @invoice.file.attached?

          # Create notification for new invoice/product
          if @invoice.product_name.present?
            NotificationService.create_product_added_notification(current_user, @invoice.product_name)
          end

          render json: {
            invoice: invoice_data(@invoice),
            message: @invoice.file.attached? ? "Invoice uploaded successfully. OCR processing started." : "Invoice created successfully",
            ocr_status: @invoice.ocr_status
          }, status: :created
        else
          render json: { error: @invoice.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      # PUT /api/v1/invoices/:id
      def update
        if params[:file].present?
          @invoice.original_filename = params[:file].original_filename
          @invoice.file.attach(params[:file])
          @invoice.ocr_status = :pending
        end

        if @invoice.update(invoice_params)
          InvoiceOcrJob.perform_later(@invoice.id) if params[:file].present?

          render json: {
            invoice: invoice_data(@invoice),
            message: params[:file].present? ? "Invoice updated and OCR processing started" : "Invoice updated successfully"
          }
        else
          render json: { error: @invoice.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/invoices/:id
      def destroy
        @invoice.destroy!
        render json: { message: "Invoice deleted successfully" }
      end

      # GET /api/v1/invoices/:id/download
      def download
        if @invoice.file.attached?
          blob = @invoice.file.blob

          # Use send_data for API controllers (send_blob is for full Rails)
          send_data blob.download,
            filename: blob.filename.to_s,
            type: blob.content_type,
            disposition: "attachment"
        else
          render json: { error: "No file attached" }, status: :not_found
        end
      end

      # GET /api/v1/invoices/:id/preview
      # View invoice in browser (PDF viewer or image display)
      def preview
        if @invoice.file.attached?
          blob = @invoice.file.blob

          # Send inline for browser display
          send_data blob.download,
            filename: blob.filename.to_s,
            type: blob.content_type,
            disposition: "inline"  # Inline displays in browser instead of downloading
        else
          render json: { error: "No file attached" }, status: :not_found
        end
      end

      # GET /api/v1/invoices/stats
      def stats
        invoices = current_user.invoices

        stats = {
          total: invoices.count,
          active: invoices.where(warranty_status: :active).count,
          expiring_soon: invoices.where(warranty_status: :expiring_soon).count,
          expired: invoices.where(warranty_status: :expired).count,
          total_value: invoices.sum(:amount) || 0
        }

        render json: { stats: stats }
      end

      # GET /api/v1/dashboard
      # Comprehensive dashboard data with warranty breakdown
      def dashboard
        invoices = current_user.invoices.includes(:product_warranties)

        # Active warranties
        active_invoices = invoices.where(warranty_status: :active)
        active_warranties_count = active_invoices.count
        active_warranties_value = active_invoices.sum(:amount) || 0

        # Expiring soon (within 30 days)
        expiring_soon_invoices = invoices.where(warranty_status: :expiring_soon)
        expiring_soon_count = expiring_soon_invoices.count

        # Expired
        expired_invoices = invoices.where(warranty_status: :expired)
        expired_count = expired_invoices.count

        # Component warranties breakdown
        component_warranties = current_user.product_warranties
          .includes(invoice: :user)
          .group_by(&:component_name)

        # Recent invoices
        recent_invoices = invoices.order(created_at: :desc).limit(5)

        # Upcoming expirations (next 30 days)
        upcoming_expirations = current_user.product_warranties.expiring_soon
          .includes(:invoice)
          .limit(10)

        render json: {
          dashboard: {
            summary: {
              total_invoices: invoices.count,
              total_value: invoices.sum(:amount) || 0,
              active_warranties: active_warranties_count,
              active_value: active_warranties_value,
              expiring_soon: expiring_soon_count,
              expired: expired_count
            },
            by_component: component_warranties.map do |component, warranties|
              {
                component: component,
                total: warranties.count,
                active: warranties.count { |w| w.active? },
                expiring_soon: warranties.count { |w| w.expiring_soon? },
                expired: warranties.count { |w| w.expired? }
              }
            end,
            recent_invoices: recent_invoices.map { |inv| invoice_data(inv) },
            upcoming_expirations: upcoming_expirations.map do |pw|
              {
                id: pw.id,
                component: pw.component_name,
                component_display: pw.component_display_name,
                product_name: pw.invoice.product_name,
                brand: pw.invoice.brand,
                expires_at: pw.expires_at,
                days_remaining: pw.days_remaining,
                warranty_months: pw.warranty_months,
                invoice_id: pw.invoice_id
              }
            end
          }
        }
      end

      # POST /api/v1/invoices/:id/retry_ocr
      def retry_ocr
        unless @invoice.file.attached?
          return render json: { error: "No file attached for OCR" }, status: :unprocessable_entity
        end

        @invoice.update(ocr_status: :pending, ocr_error_message: nil)
        InvoiceOcrJob.perform_later(@invoice.id)

        render json: {
          message: "OCR processing restarted",
          ocr_status: @invoice.ocr_status
        }
      end

      # GET /api/v1/invoices/:id/ocr_status
      def ocr_status
        render json: {
          invoice_id: @invoice.id,
          ocr_status: @invoice.ocr_status,
          ocr_error_message: @invoice.ocr_error_message,
          ocr_data: @invoice.ocr_data_hash,
          extracted_fields: {
            product_name: @invoice.product_name,
            brand: @invoice.brand,
            seller: @invoice.seller,
            amount: @invoice.amount,
            purchase_date: @invoice.purchase_date,
            warranty_duration: @invoice.warranty_duration
          }
        }
      end

      private

      def set_invoice
        @invoice = current_user.invoices.find_by(id: params[:id])
        return if @invoice

        render json: { error: "Invoice not found" }, status: :not_found
      end

      def invoice_params
        # Handle both wrapped (JSON) and flat (FormData) params
        p = params.key?(:invoice) ? params.require(:invoice) : params
        p.permit(:product_name, :brand, :model_number, :seller, :amount, :purchase_date,
                 :warranty_duration, :category, :file, :ocr_status)
      end

      def invoice_data(invoice, include_warranties: false)
        data = {
          id:                 invoice.id,
          product_name:       invoice.product_name,
          brand:              invoice.brand,
          model_number:       invoice.model_number,
          seller:             invoice.seller,
          amount:             invoice.amount&.to_f,
          formatted_amount:   invoice.formatted_amount,
          purchase_date:      invoice.purchase_date,
          warranty_duration:  invoice.warranty_duration,
          warranty_status:    invoice.warranty_status,
          expires_at:         invoice.expires_at,
          days_remaining:     invoice.days_remaining,
          category:           invoice.category,
          product_image_url:  invoice.product_image_url,
          description:        invoice.description,
          original_filename:  invoice.original_filename,
          ocr_status:         invoice.ocr_status,
          ocr_error_message:  invoice.ocr_error_message,
          has_file:           invoice.file.attached?,
          file_url:           invoice.file.attached? ? Rails.application.routes.url_helpers.rails_blob_url(invoice.file, host: api_host) : nil,
          created_at:         invoice.created_at,
          updated_at:         invoice.updated_at
        }

        if include_warranties
          data[:product_warranties] = invoice.product_warranties.order("product_warranties.expires_at ASC").map do |pw|
            {
              id:               pw.id,
              component_name:   pw.component_name,
              component_display: pw.component_display_name,
              warranty_months:  pw.warranty_months,
              formatted_duration: pw.formatted_duration,
              expires_at:       pw.expires_at,
              days_remaining:   pw.days_remaining,
              status:           pw.active? ? "active" : (pw.expired? ? "expired" : "expiring_soon"),
              reminder_sent:    pw.reminder_sent
            }
          end
        end

        data
      end

      def api_host
        ENV.fetch("APP_URL", request.base_url)
      end
    end
  end
end
