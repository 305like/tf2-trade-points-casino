"""Exercise the deployed game-wallet SQL in isolated SQLite; no live balances."""
from pathlib import Path
import re,sqlite3
s=Path('addons/sourcemod/scripting/game_points.inc').read_text(encoding='utf-8')
q=re.findall(r'Format\(q,sizeof\(q\),"([^"\n]+)"',s)
def statement(prefix): return next(x for x in q if x.startswith(prefix))
db=sqlite3.connect(':memory:')
for ddl in re.findall(r'SQL_FastQuery\(g_DB,"(CREATE [^"]+)"',s):db.execute(ddl)
id='76561198038759714'
db.execute('INSERT INTO play_accounts VALUES(?,10)',(id,));db.commit()
def stake(n):
 db.execute('BEGIN IMMEDIATE');db.execute(statement('INSERT INTO play_rounds')%(id,n,n,id,n,id));changed=db.execute('SELECT changes()').fetchone()[0]
 if not changed:db.rollback();return None
 rid=db.execute('SELECT id FROM play_rounds WHERE closed=0').fetchone()[0]
 db.execute(statement('UPDATE play_accounts SET points=points-')%(n,id));db.commit();return rid
def roll(rid,win):
 amount=db.execute('SELECT amount FROM play_rounds WHERE id=? AND closed=0',(rid,)).fetchone()[0];result=amount*2 if win else 0
 db.execute(statement('UPDATE play_rounds SET amount=')%(result,int(result==0),rid));db.commit();return result
def cash(rid):
 db.execute('BEGIN IMMEDIATE');r=db.execute('SELECT amount FROM play_rounds WHERE id=? AND closed=0',(rid,)).fetchone()
 if not r:db.rollback();return False
 db.execute(statement('UPDATE play_accounts SET points=points+%d')%(r[0],id));db.execute(statement('UPDATE play_rounds SET closed=1 WHERE id=')%rid);db.commit();return True
r=stake(3);assert db.execute('SELECT points FROM play_accounts').fetchone()[0]==7
assert stake(1) is None
assert roll(r,True)==6;assert roll(r,True)==12;assert cash(r);assert not cash(r)
assert db.execute('SELECT points FROM play_accounts').fetchone()[0]==19
r=stake(5);assert roll(r,False)==0;assert not cash(r)
assert db.execute('SELECT points FROM play_accounts').fetchone()[0]==14
assert stake(15) is None
r=stake(1);roll(r,True)
recovery=statement('UPDATE play_accounts SET points=points+COALESCE')%''
db.execute(recovery);db.execute('UPDATE play_rounds SET closed=1 WHERE closed=0');db.commit()
assert db.execute('SELECT points FROM play_accounts').fetchone()[0]==15
assert not re.search(r'(?:FROM|INTO|UPDATE) accounts\b',s)
print('PASS actual SQL: stake, insufficient funds, one active round, double, loss, collect once, restart recovery, isolated ledger')
