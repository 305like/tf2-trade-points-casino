"""Execute the actual SourcePawn adjustment SQL against an isolated SQLite ledger."""
from pathlib import Path
import re
import sqlite3

source=Path('addons/sourcemod/scripting/metal_points_shop.inc').read_text(encoding='utf-8')
queries=re.findall(r'Format\(query,sizeof\(query\),"([^"]+)"',source)
insert=next(q for q in queries if q.startswith('INSERT INTO wallet_actions SELECT') and "'play_adjust'" in q)
update=next(q for q in queries if q.startswith('UPDATE play_accounts SET points=points+'))
db=sqlite3.connect(':memory:')
db.executescript('''CREATE TABLE play_accounts(steamid TEXT PRIMARY KEY,points INTEGER NOT NULL CHECK(points BETWEEN 0 AND 2000000000));
CREATE TABLE wallet_actions(code TEXT PRIMARY KEY,actor TEXT,target TEXT,kind TEXT,amount INTEGER,created INTEGER,balance INTEGER);
INSERT INTO play_accounts VALUES('76561199077147589',90);''')
owner='76561198038759714';target='76561199077147589'
def change(code,amount):
    db.execute('BEGIN IMMEDIATE')
    try:
        if db.execute('SELECT 1 FROM wallet_actions WHERE code=?',(code,)).fetchone():
            db.rollback();return
        db.execute(insert%(code,owner,target,amount,'1234567890',amount,target,amount))
        db.execute(update%(amount,target,code))
        if not db.execute('SELECT 1 FROM wallet_actions WHERE code=?',(code,)).fetchone():
            db.rollback();return
        db.commit()
    except Exception:
        db.rollback();raise
change('a'*32,90);change('a'*32,90)
assert db.execute('SELECT points FROM play_accounts').fetchone()[0]==180
assert db.execute('SELECT COUNT(*) FROM wallet_actions').fetchone()[0]==1
change('b'*32,-181)
assert db.execute('SELECT points FROM play_accounts').fetchone()[0]==180
change('c'*32,-180)
assert db.execute('SELECT points FROM play_accounts').fetchone()[0]==0
assert 'if(adjust&&!StrEqual(v[1],POINT_OWNER))return true;' in source
assert 'if(withdraw&&!StrEqual(v[1],v[2]))return true;' in source
assert 'WalletSnapshot();GamePointsSnapshot();ExportOutgoing();' in source
print('PASS actual wallet SQL: owner audit, replay idempotence, nonnegative balance and atomic rollback')
