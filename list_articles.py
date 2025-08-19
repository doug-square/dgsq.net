import os
import sys

try: 
    from BeautifulSoup import BeautifulSoup
except ImportError:
    from bs4 import BeautifulSoup

months = {
  1: "Jan",
  2: "Feb",
  3: "Mar",
  4: "Apr",
  5: "May",
  6: "Jun",
  7: "Jul",
  8: "Aug",
  9: "Sep",
  10: "Oct",
  11: "Nov",
  12: "Dec",
}

posts = []

for subdir, dirs, files in os.walk('src/pages/posts'):
    for file in files:
        if ".html" not in file:
            continue

        try:
            year, month, day = file.split('-')[:3]
            year = int(year)
            month = int(month)
            day = int(day)
        except:
            continue

        with open(os.path.join(subdir, file)) as f:
            html = BeautifulSoup(f.read(), features="lxml")
            title, _, _ = html.body.find('ul', attrs={'class': 'blog-title'}).find_all('li')
            title = title.text

        base_path = "/".join([""] + subdir.split("/")[2:])
        path = os.path.join(base_path, file)

        posts.append((year, month, day, title, path))

posts = list(reversed(sorted(posts)))

postlist = []
for year, month, day, title, path in posts:
    date = f"{months[month]} {day}, {year}"
    postlist.append(f"<li><a href=\"{path}\">{title}</a> ({date})</li>")

postlist = "\n".join(postlist)

# Insert the posts into the generated html
with open("public/posts/index.html") as f:
    html = BeautifulSoup(f.read(), features="lxml")
    posts_div = html.body.find('ul', attrs={'id': 'posts'})
    posts_div.append(BeautifulSoup(postlist, "html.parser"))

with open("public/posts/index.html", "w") as f:
    f.write(html.prettify())

