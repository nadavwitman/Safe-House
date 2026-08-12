from database.repositories.client import db


def get_baseline(house_id='default_house'):
    """Returns the EMA baseline dict for the house, or None if not yet established."""
    doc = db.collection('houses').document(house_id).get()
    if doc.exists:
        return doc.to_dict().get('baseline')
    return None


def save_baseline(house_id, baseline):
    """Persists the EMA baseline to the house document without overwriting other fields."""
    db.collection('houses').document(house_id).set(
        {'baseline': baseline},
        merge=True
    )


def save_weekly_report(house_id, report_dict):
    """Saves the weekly report to the house document."""
    db.collection('houses').document(house_id).set(
        {'weekly_report': report_dict}, merge=True
    )


def get_weekly_report(house_id):
    """Returns the last saved weekly report for a house, or None if none exists."""
    doc = db.collection('houses').document(house_id).get()
    if not doc.exists:
        return None
    return doc.to_dict().get('weekly_report')
