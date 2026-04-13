# frozen_string_literal: true

# Loaded automatically by `rake console` (pry).
# Auto-formats Sequel model arrays as readable tables via table_print.
# Dev-only convenience; has no effect on the app or tests.

require 'table_print'

# Per-model default columns, so show sensible, non-overflowing output.
MODEL_COLUMNS = {
  'LockedCV::User' => %i[id first_name last_name phone_number],
  'LockedCV::File' => %i[id file_name route user_id],
  'LockedCV::SensitiveData' => %i[id user_name phone_number birthday email address identification_numbers file_id]
}.freeze

# Make auto-render as tables in pry, the way Hirb used to.
# Falls back to the default printer for everything else.
#
# NOTE: TablePrint::Printer.table_print returns a STRING and does not
# write to stdout itself — only the top-level `tp` helper puts it.
# Inside a Pry.config.print hook we have to write to `output` ourselves.
old_print = Pry.config.print

Pry.config.print = proc do |output, value, *rest|
  if value.is_a?(Array) && !value.empty? && value.first.is_a?(Sequel::Model)
    model_class = value.first.class.name
    columns = MODEL_COLUMNS[model_class]

    if columns
      output.puts TablePrint::Printer.table_print(value, columns)
    else
      output.puts TablePrint::Printer.table_print(value)
    end
  else
    old_print.call(output, value, *rest)
  end
end

puts 'table_print enabled - Sequel model arrays auto-render as tables.'
