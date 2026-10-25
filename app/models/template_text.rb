# A small email template: the first line is "Subject: ...", then a body in a
# little Markdown (paragraphs, `code`, **bold**, <https://links>, and "- "
# lists), with {{variables}}. A missing variable raises, so an email is never
# sent with a hole in it. Times in ISO 8601 also get a "_date" variable
# ("25 April 2027").
class TemplateText
  class MissingVariable < StandardError; end

  attr_reader :subject, :text

  def initialize(source, variables)
    vars = expand(variables)
    lines = source.to_s.lines
    raise ArgumentError, "a template starts with a Subject: line" unless lines.first.to_s.start_with?("Subject:")
    @subject = fill(lines.first.delete_prefix("Subject:").strip, vars)
    @text = fill(lines.drop(1).join.strip, vars)
    @vars = vars
  end

  def html
    paragraphs = @text.split(/\n{2,}/).map do |block|
      if block.lines.all? { |line| line.start_with?("- ") }
        items = block.lines.map { |line| "<li style=\"margin:0 0 6px\">#{inline(line.delete_prefix("- ").strip)}</li>" }
        "<ul style=\"margin:0 0 16px;padding-left:20px\">#{items.join}</ul>"
      else
        "<p style=\"margin:0 0 16px\">#{block.lines.map { |line| inline(line.strip) }.join("<br>")}</p>"
      end
    end
    paragraphs.join("\n").html_safe
  end

  private

  def expand(variables)
    variables.to_h.transform_keys(&:to_s).each_with_object({}) do |(key, value), vars|
      vars[key] = value.to_s
      time = (Time.iso8601(value.to_s) rescue nil) if value.is_a?(String) && value.match?(/\A\d{4}-\d\d-\d\dT/)
      vars["#{key}_date"] = time.utc.strftime("%-d %B %Y") if time
    end
  end

  def fill(text, vars)
    text.gsub(/\{\{\s*([a-z0-9_]+)\s*\}\}/) { vars.fetch(Regexp.last_match(1)) { raise MissingVariable, "no value for {{#{Regexp.last_match(1)}}}" } }
  end

  def inline(text)
    escaped = ERB::Util.html_escape(text)
    escaped
      .gsub(/&lt;(https?:\/\/[^\s&]+)&gt;/) { %(<a href="#{Regexp.last_match(1)}" style="color:inherit;word-break:break-all">#{Regexp.last_match(1)}</a>) }
      .gsub(/`([^`]+)`/) { %(<code style="font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:15px;background:rgba(0,0,0,.06);padding:2px 6px;border-radius:5px;word-break:break-all">#{Regexp.last_match(1)}</code>) }
      .gsub(/\*\*([^*]+)\*\*/) { "<strong>#{Regexp.last_match(1)}</strong>" }
  end
end
