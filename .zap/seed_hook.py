# zap-baseline hook (--hook): the server is a JSON API with no links to
# spider, so its endpoints are requested here and the passive scanner sees
# their answers. ZAP_COOKIE (optional): a logged-in session for the
# protected endpoints. Alerts accepted precisely (rule id, parameter), not
# a whole rule as in rules.tsv: XSRF-TOKEN has no HttpOnly on purpose
# (the app's scripts read it and send it back in X-XSRF-TOKEN).
import os

ACCEPTED = {('10010', 'XSRF-TOKEN')}

SEEDS = [
    '/', '/robots.txt',
    '/api/books', '/api/books?q=dune&page=0', '/api/books/9780451524935',
    '/api/books/9780451524935/cover', '/api/books/0000000000000',
    '/api/books/recent', '/api/me', '/api/orders', '/api/orders/recent',
    '/api/basket', '/api/admin/logs', '/api/admin/orders/live',
    '/api/login', '/api/logout', '/login',
    '/supplier/offers/9780451524935', '/ws/support',
    '/oauth2/authorization/keycloak', '/login/oauth2/code/keycloak?code=x&state=y',
    '/api/stock/events',  # server-sent events: open until ZAP's read timeout
]


def zap_started(zap, target):
    cookie = os.environ.get('ZAP_COOKIE')
    if cookie:
        zap.replacer.add_rule(
            description='session', enabled='true', matchtype='REQ_HEADER',
            matchregex='false', matchstring='Cookie', replacement=cookie)
    base = target.rstrip('/')
    for path in SEEDS:
        try:
            zap.core.access_url(url=base + path, followredirects='false')
        except Exception as error:  # the next seed still runs
            print('seed failed', path, error)


def zap_get_alerts_wrap(alert_dict):
    """Drops the accepted alerts before the baseline counts them (in place:
    the baseline ignores what a one-argument hook returns)."""
    for rule in list(alert_dict):
        alert_dict[rule] = [
            a for a in alert_dict[rule] if (rule, a.get('param')) not in ACCEPTED
        ]
        if not alert_dict[rule]:
            del alert_dict[rule]
