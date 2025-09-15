from feedgen.feed import FeedGenerator

class Article:
    def __init__(self, title, date, url):
        self.title = title
        self.date = date
        self.url = url


def create_feed(articles):
    fg = FeedGenerator()
    fg.id('dgsq.net')
    fg.title('dgsq')
    fg.description(description="Whereupon dgsq writes")
    fg.link(href='https://dgsq.net/', rel='alternate')
    fg.link(href='https://dgsq.net/rss.xml', rel='self')
    fg.language('en')
    
    for article in articles:
        fe = fg.add_entry()
        fe.id(article.url)
        fe.title(article.title)
        fe.description(description=article.title)
        fe.link(href=article.url)
        fe.published(article.date + " 12:00:00 CST")
    
    return fg.rss_str(pretty=True)

