# A Mechanize based Sidekiq Worker that reports on new bid announcements in Norway
#
# This is used in a Rails app with a Bid model for storing known bids,
# and a BidMailer to send bid announcements to an email.
#
class BidWorker
  include Sidekiq::Worker
  sidekiq_options unique: true

  def perform
    started_at = Time.now
    agent = Mechanize.new

    cpv = [15100000, 15110000, 15112000, 15130000, 15131000, 15131700, 15894600]

    url = "https://www.doffin.no"
    path  = "/Notice?NoticeType=2&IncludeExpired=false&Cpvs=#{cpv.join("+")}"

    agent.get(url+path)

    doc = Nokogiri::HTML(agent.page.content)

    # Fix links
    doc.xpath("//*[@href]").each do |lnk|
      dest = lnk.attributes["href"].value
      lnk.attributes["href"].value = url + dest
      lnk.remove if dest == "#"
    end

    bids = doc.css(".notice-search-item")

    # Clean up markup
    bids.each do |bid|
      bid.xpath('//script').remove
      bid.xpath('//img').remove
      bid.at_css('i').parent.remove
      bid.xpath('//*[@class="inline"]').each do |div|
        div.attributes["class"].remove
        div["style"] = "padding-left: 1em;"
      end
    end

    new_bids = []

    # Build the Bid
    bids.each do |bd|
      html = bd.to_html
      ref = html =~ /Doffin referanse/
      pref = html[ref..ref+28]

      bid = Bid.find_or_initialize_by(reference: pref)
      if bid.new_record?
        bid.html = html
        bid.save
        new_bids << bid
      end
    end

    # Send email
    mail = BidMailer.send_bids("anbud@eksempel.no", new_bids, url+path)
    mail.deliver unless new_bids.empty?

    logger.info "Time spent #{Time.now - started_at}"
  end
end
