# frozen_string_literal: true

module LockedCV
  # Builds a new PDF from positioned text, replacing sensitive values before writing text.
  class BuildVisualMaskedPdf
    DEFAULT_PAGE_WIDTH = 612
    DEFAULT_PAGE_HEIGHT = 792

    def self.call(fragments:, boxes:, values:)
      new(fragments:, boxes:, values:).call
    end

    def initialize(fragments:, boxes:, values:)
      @fragments = fragments
      @boxes = boxes
      @values = values.sort_by { |value| [-value.length, value.downcase] }
    end

    def call
      page_numbers = (fragment_page_numbers + box_page_numbers).uniq.sort
      build_pdf(page_numbers:)
    end

    private

    attr_reader :fragments, :boxes, :values

    def fragment_page_numbers
      fragments.map { |fragment| fragment[:page_number] }
    end

    def box_page_numbers
      boxes.map { |box| box[:page_number] }
    end

    def build_pdf(page_numbers:)
      objects = []
      add_object(objects, '')
      add_object(objects, '')
      font_id = add_object(objects, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>')
      page_ids = page_numbers.map { |page_number| add_page(objects:, page_number:, font_id:) }
      objects[0] = '<< /Type /Catalog /Pages 2 0 R >>'
      objects[1] = "<< /Type /Pages /Kids [#{page_ids.map { |id| "#{id} 0 R" }.join(' ')}] /Count #{page_ids.length} >>"
      serialize_pdf(objects)
    end

    def add_page(objects:, page_number:, font_id:)
      content = page_content(page_number)
      content_id = add_object(
        objects,
        "<< /Length #{content.bytesize} >> stream\n#{content}endstream"
      )
      add_object(objects, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] ' \
                          "/Resources << /Font << /F1 #{font_id} 0 R >> >> /Contents #{content_id} 0 R >>")
    end

    def add_object(objects, body)
      objects << body
      objects.length
    end

    def page_content(page_number)
      text_stream = fragments_for(page_number).map { |fragment| text_operator(fragment) }.join("\n")
      # Temporarily disable drawing white mask boxes; the generated text layer
      # is still scrubbed before output so sensitive values are not preserved.
      # box_stream = boxes_for(page_number).map { |box| mask_operator(box) }.join("\n")
      "#{text_stream}\n"
    end

    def fragments_for(page_number)
      fragments.select { |fragment| fragment[:page_number] == page_number }
    end

    def boxes_for(page_number)
      boxes.select { |box| box[:page_number] == page_number }
    end

    def text_operator(fragment)
      text = scrubbed_text(fragment[:text])
      format(
        'BT /F1 %<height>.2f Tf %<x>.2f %<y>.2f Td (%<text>s) Tj ET',
        height: fragment[:height],
        x: fragment[:x],
        y: fragment[:y],
        text: pdf_escape(text)
      )
    end

    def mask_operator(box)
      format(
        'q 1 1 1 rg %<x>.2f %<y>.2f %<width>.2f %<height>.2f re f Q',
        x: box[:x],
        y: box[:y],
        width: box[:width],
        height: box[:height]
      )
    end

    def scrubbed_text(text)
      values.reduce(text.to_s) do |scrubbed, value|
        scrubbed.gsub(/#{Regexp.escape(value)}/i) { |match| ' ' * match.length }
      end
    end

    def pdf_escape(text)
      text.gsub('\\', '\\\\\\').gsub('(', '\\(').gsub(')', '\\)')
    end

    def serialize_pdf(objects)
      body = +"%PDF-1.4\n"
      offsets = objects.map.with_index(1) do |object, index|
        offset = body.bytesize
        body << "#{index} 0 obj #{object} endobj\n"
        offset
      end
      append_xref(body:, offsets:)
    end

    def append_xref(body:, offsets:)
      xref_offset = body.bytesize
      body << "xref\n0 #{offsets.length + 1}\n0000000000 65535 f \n"
      offsets.each { |offset| body << format('%010d 00000 n ', offset) << "\n" }
      body << "trailer << /Root 1 0 R /Size #{offsets.length + 1} >>\n"
      body << "startxref\n#{xref_offset}\n%%EOF\n"
    end
  end
end
