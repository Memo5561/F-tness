"""Eigene Calisthenics-Übungen, die in der freien Übungsdatenbank fehlen.

Jede Übung hat eine animierte Strichfigur (frames). Winkel in Grad: 0 = rechts, 90 = oben.
t = Hüfte->Schulter, ua/la = Ober-/Unterarm, th/sh = Oberschenkel/Schienbein.
Suffix 1 = vorderer (naher) Arm/Bein, 2 = hinterer Arm/Bein.
"""

FLOOR = 88


def A(**kw):
    base = dict(t=90, ua=270, la=270, th=270, sh=270)
    out = {}
    for k in ('t', 'hd'):
        if k in kw:
            out[k] = kw[k]
    out.setdefault('t', base['t'])
    for k in ('ua', 'la', 'th', 'sh'):
        v = kw.get(k, base[k])
        out[k + '1'] = kw.get(k + '1', v)
        out[k + '2'] = kw.get(k + '2', v)
    return out


def F(at, **kw):
    return {'at': list(at), 'a': A(**kw)}


floor = {'k': 'floor', 'y': FLOOR}


def bar(x=50, y=12):
    return {'k': 'bar', 'x': x, 'y': y}


def pbars(y=52, x1=25, x2=80):
    return {'k': 'pbars', 'y': y, 'x1': x1, 'x2': x2, 'floor': FLOOR}


def wall(x):
    return {'k': 'wall', 'x': x, 'floor': FLOOR}


def box(x, y, w, h):
    return {'k': 'box', 'x': x, 'y': y, 'w': w, 'h': h}


def pole(x):
    return {'k': 'pole', 'x': x, 'floor': FLOOR}


# ---------------------------------------------------------------- Grundposen
HANG = dict(t=90, ua=94, la=94, th=268, sh=268)
PULL_TOP = dict(t=96, ua=285, la=100, th=262, sh=262)
PULL_MID = dict(t=93, ua=20, la=110, th=265, sh=265)
PUSH_TOP = dict(t=24, ua=270, la=270, th=204, sh=204)
PUSH_BOT = dict(t=13, ua=205, la=300, th=193, sh=193)
DIP_TOP = dict(t=86, ua=272, la=270, th=262, sh=215)
DIP_BOT = dict(t=66, ua=205, la=300, th=250, sh=200)
STAND = dict(t=90)

EX = []


def ex(id, name, cat, eq, lvl, pm, sm, ins, anchor, frames, props, mode='r', loop='pingpong', speed=1.0, en=None):
    EX.append(dict(id=id, n=name, en=en or name, cat=cat, eq=eq, lvl=lvl, pm=pm, sm=sm, ins=ins,
                   mode=mode, anim=dict(anchor=anchor, frames=frames, props=props, loop=loop, speed=speed)))


# ---------------------------------------------------------------- Zug (Pull)
ex('cal_dead_hang', 'Toter Hang (Dead Hang)', 'calisthenics', 'pull-up bar', 'beginner',
   ['forearms'], ['lats', 'shoulders'],
   ['Greife die Stange schulterbreit im Obergriff.',
    'Lass dich mit gestreckten Armen hängen, die Füße berühren nicht den Boden.',
    'Atme ruhig weiter und halte die Position für die vorgegebene Zeit.',
    'Fortgeschritten: Ziehe die Schultern leicht nach unten (aktiver Hang).'],
   'w1', [F((50, 12), **HANG), F((50, 12), **dict(HANG, t=92, th=272, sh=272))], [bar()], mode='t', speed=0.4)

ex('cal_flexed_arm_hang', 'Halten oben (Flexed Arm Hang)', 'calisthenics', 'pull-up bar', 'beginner',
   ['lats', 'biceps'], ['forearms', 'middle back'],
   ['Spring oder steig hoch, bis dein Kinn über der Stange ist.',
    'Halte diese Position mit angespannter Körpermitte.',
    'Ziehe die Ellbogen eng zum Körper und die Schultern nach unten.',
    'Halte so lange wie möglich, dann lass dich kontrolliert ab.'],
   'w1', [F((50, 12), **PULL_TOP), F((50, 12), **dict(PULL_TOP, t=98, th=265, sh=265))], [bar()], mode='t', speed=0.4)

ex('cal_negative_pullup', 'Negative Klimmzüge', 'calisthenics', 'pull-up bar', 'beginner',
   ['lats'], ['biceps', 'middle back', 'forearms'],
   ['Spring oder steig hoch, bis dein Kinn über der Stange ist.',
    'Lass dich so langsam wie möglich (3–5 Sekunden) ab, bis die Arme gestreckt sind.',
    'Halte die Körpermitte fest und vermeide Schwung.',
    'Steig wieder hoch und wiederhole die Bewegung.'],
   'w1', [F((50, 12), **PULL_TOP), F((50, 12), **PULL_MID), F((50, 12), **HANG)], [bar()], speed=0.45)

ex('cal_archer_pullup', 'Archer-Klimmzug', 'calisthenics', 'pull-up bar', 'expert',
   ['lats'], ['biceps', 'middle back', 'shoulders'],
   ['Greife die Stange sehr weit im Obergriff.',
    'Ziehe dich zu einer Hand hoch, während der andere Arm fast gestreckt zur Seite zeigt.',
    'Kinn über die Stange, dann kontrolliert absenken.',
    'Wechsle die Seite nach jeder Wiederholung oder jedem Satz.'],
   'w1', [F((50, 12), **HANG), F((50, 12), **dict(PULL_TOP, ua2=40, la2=40))], [bar()], speed=0.6)

ex('cal_high_pullup', 'Explosive Klimmzüge (High Pull-Up)', 'calisthenics', 'pull-up bar', 'intermediate',
   ['lats'], ['biceps', 'middle back', 'shoulders'],
   ['Hänge mit gestreckten Armen an der Stange.',
    'Ziehe dich explosiv so hoch wie möglich, die Stange soll Brust oder Bauch berühren.',
    'Ziehe die Ellbogen dabei weit nach hinten-unten.',
    'Kontrolliert ablassen. Das ist die wichtigste Vorübung für den Muscle-Up.'],
   'w1', [F((50, 12), **HANG), F((50, 12), **dict(t=108, ua=305, la=75, th=258, sh=258))], [bar()], speed=0.9)

ex('cal_negative_muscle_up', 'Negativer Muscle-Up', 'calisthenics', 'pull-up bar', 'intermediate',
   ['lats', 'triceps'], ['chest', 'shoulders', 'biceps'],
   ['Spring in den Stütz über der Stange (Arme gestreckt).',
    'Lass dich langsam über den Übergang ab, bis die Brust an der Stange ist.',
    'Senke dich weiter kontrolliert in den Hang ab.',
    'Je langsamer, desto besser für den Aufbau der Übergangskraft.'],
   'w1', [F((50, 12), **dict(t=80, ua=270, la=270, th=262, sh=262)),
          F((50, 12), **dict(t=70, ua=200, la=60, th=255, sh=255)),
          F((50, 12), **dict(t=108, ua=305, la=75, th=258, sh=258)),
          F((50, 12), **HANG)], [bar()], loop='cycle', speed=0.45)

ex('cal_strict_muscle_up', 'Muscle-Up (strikt)', 'calisthenics', 'pull-up bar', 'expert',
   ['lats', 'triceps'], ['chest', 'shoulders', 'biceps', 'abdominals'],
   ['Hänge an der Stange mit falschem oder normalem Griff.',
    'Ziehe dich explosiv hoch, bis die Stange auf Brusthöhe ist.',
    'Lehne den Oberkörper über die Stange und drücke dich in den Stütz hoch.',
    'Strecke die Arme oben komplett und lass dich kontrolliert zurück in den Hang.'],
   'w1', [F((50, 12), **HANG),
          F((50, 12), **dict(t=108, ua=305, la=75, th=258, sh=258)),
          F((50, 12), **dict(t=70, ua=200, la=60, th=255, sh=255)),
          F((50, 12), **dict(t=80, ua=270, la=270, th=262, sh=262))], [bar()], loop='cycle', speed=0.7)

# ---------------------------------------------------------------- Druck (Push)
ex('cal_wall_pushup', 'Wand-Liegestütz', 'calisthenics', 'body only', 'beginner',
   ['chest'], ['triceps', 'shoulders'],
   ['Stell dich eine Armlänge vor eine Wand und lege die Hände schulterbreit auf Brusthöhe an.',
    'Halte den Körper gerade wie ein Brett.',
    'Beuge die Arme, bis die Brust fast die Wand berührt.',
    'Drücke dich zurück in die Ausgangsposition.'],
   'w1', [F((80, 40), **dict(t=72, ua=0, la=0, th=252, sh=252)),
          F((80, 40), **dict(t=62, ua=315, la=40, th=242, sh=242))], [wall(81), floor])

ex('cal_knee_pushup', 'Knie-Liegestütz', 'calisthenics', 'body only', 'beginner',
   ['chest'], ['triceps', 'shoulders'],
   ['Geh in den Vierfüßlerstand und setz die Hände etwas breiter als schulterbreit auf.',
    'Wandere mit den Knien zurück, bis Knie, Hüfte und Schultern eine Linie bilden.',
    'Senke die Brust kontrolliert Richtung Boden, die Ellbogen zeigen schräg nach hinten.',
    'Drücke dich wieder hoch, bis die Arme gestreckt sind.'],
   'w1', [F((70, FLOOR), **dict(t=34, ua=270, la=270, th=214, sh=165)),
          F((70, FLOOR), **dict(t=18, ua=205, la=300, th=198, sh=172))], [floor])

ex('cal_diamond_pushup', 'Diamant-Liegestütz', 'calisthenics', 'body only', 'intermediate',
   ['triceps'], ['chest', 'shoulders'],
   ['Setz die Hände unter der Brust so auf, dass Daumen und Zeigefinger eine Raute bilden.',
    'Spanne Bauch und Gesäß an, der Körper bildet eine gerade Linie.',
    'Senke dich ab, bis die Brust die Hände fast berührt. Die Ellbogen bleiben eng am Körper.',
    'Drücke dich kraftvoll wieder hoch.'],
   'w1', [F((68, FLOOR), **PUSH_TOP), F((68, FLOOR), **PUSH_BOT)], [floor])

ex('cal_archer_pushup', 'Archer-Liegestütz', 'calisthenics', 'body only', 'intermediate',
   ['chest'], ['triceps', 'shoulders'],
   ['Setz die Hände sehr weit auseinander auf.',
    'Senke dich zu einer Hand ab, während der andere Arm gestreckt bleibt.',
    'Drücke dich wieder hoch und wechsle die Seite.',
    'Vorübung für den einarmigen Liegestütz.'],
   'w1', [F((68, FLOOR), **PUSH_TOP), F((68, FLOOR), **PUSH_BOT)], [floor])

ex('cal_pike_pushup', 'Pike-Liegestütz', 'calisthenics', 'body only', 'intermediate',
   ['shoulders'], ['triceps', 'chest'],
   ['Geh in den Liegestütz und schieb die Hüfte weit nach oben, sodass ein umgedrehtes V entsteht.',
    'Die Hände sind schulterbreit, der Blick geht Richtung Füße.',
    'Beuge die Arme und senke den Kopf vor den Händen Richtung Boden.',
    'Drücke dich zurück nach oben. Vorübung für den Handstand-Liegestütz.'],
   'w1', [F((65, FLOOR), **dict(t=340, hd=320, ua=285, la=285, th=252, sh=252)),
          F((65, FLOOR), **dict(t=318, hd=290, ua=215, la=300, th=240, sh=240))], [floor])

ex('cal_pseudo_planche_pushup', 'Pseudo-Planche-Liegestütz', 'calisthenics', 'body only', 'expert',
   ['shoulders', 'chest'], ['triceps', 'abdominals'],
   ['Setz die Hände auf Hüfthöhe auf, die Finger zeigen zur Seite oder nach hinten.',
    'Lehne die Schultern deutlich vor die Hände.',
    'Senke dich mit eng geführten Ellbogen ab, ohne die Vorlage zu verlieren.',
    'Drücke dich hoch und halte die Schultern weiter vorne.'],
   'w1', [F((55, FLOOR), **dict(t=24, ua=245, la=245, th=204, sh=204)),
          F((55, FLOOR), **dict(t=12, ua=190, la=290, th=192, sh=192))], [floor])

ex('cal_planche_lean', 'Planche Lean', 'calisthenics', 'body only', 'intermediate',
   ['shoulders'], ['chest', 'abdominals', 'forearms'],
   ['Geh in den Liegestütz, die Finger zeigen zur Seite oder nach hinten.',
    'Lehne dich so weit nach vorne, dass die Schultern deutlich vor den Händen sind.',
    'Arme gestreckt lassen, Schulterblätter auseinanderdrücken (Protraktion).',
    'Halte die Position für die vorgegebene Zeit.'],
   'w1', [F((55, FLOOR), **dict(t=22, ua=250, la=250, th=202, sh=202)),
          F((55, FLOOR), **dict(t=20, ua=240, la=240, th=200, sh=200))], [floor], mode='t', speed=0.4)

# ---------------------------------------------------------------- Dips
ex('cal_support_hold', 'Stütz halten (Barren)', 'calisthenics', 'dip bars', 'beginner',
   ['triceps'], ['shoulders', 'chest'],
   ['Stütze dich mit gestreckten Armen auf den Barren.',
    'Drücke die Schultern nach unten, weg von den Ohren.',
    'Halte den Körper ruhig und gerade.',
    'Halte die Position für die vorgegebene Zeit.'],
   'w1', [F((60, 52), **DIP_TOP), F((60, 52), **dict(DIP_TOP, t=88))], [pbars()], mode='t', speed=0.4)

ex('cal_negative_dip', 'Negative Dips', 'calisthenics', 'dip bars', 'beginner',
   ['triceps'], ['chest', 'shoulders'],
   ['Starte im Stütz am Barren mit gestreckten Armen.',
    'Senke dich in 3–5 Sekunden ab, bis die Oberarme etwa parallel zum Boden sind.',
    'Steig oder spring zurück in den Stütz.',
    'Wiederhole die Bewegung.'],
   'w1', [F((60, 52), **DIP_TOP), F((60, 52), **DIP_BOT)], [pbars()], speed=0.45)

ex('cal_straight_bar_dip', 'Dips an der Stange', 'calisthenics', 'pull-up bar', 'intermediate',
   ['triceps', 'chest'], ['shoulders'],
   ['Stütze dich auf eine gerade Stange, die Hände schulterbreit.',
    'Lehne den Oberkörper leicht nach vorne, die Beine leicht vor der Stange.',
    'Senke dich ab, bis die Stange auf Höhe der Brust ist.',
    'Drücke dich wieder in den Stütz. Wichtig für den Muscle-Up.'],
   'w1', [F((50, 40), **dict(t=80, ua=270, la=270, th=262, sh=262)),
          F((50, 40), **dict(t=62, ua=150, la=330, th=260, sh=260))], [bar(50, 40)])

# ---------------------------------------------------------------- Handstand / Balance
ex('cal_crow_pose', 'Krähe (Crow Pose)', 'calisthenics', 'body only', 'beginner',
   ['shoulders'], ['triceps', 'abdominals', 'forearms'],
   ['Geh in die Hocke und setz die Hände schulterbreit vor dir auf.',
    'Beuge die Arme leicht und setz die Knie auf die Rückseite der Oberarme.',
    'Verlagere das Gewicht nach vorne, bis die Füße abheben.',
    'Halte die Balance, der Blick geht leicht nach vorne.'],
   'w1', [F((60, FLOOR), **dict(t=20, hd=10, ua=250, la=285, th=345, sh=200)),
          F((60, FLOOR), **dict(t=18, hd=8, ua=248, la=283, th=343, sh=198))], [floor], mode='t', speed=0.4)

ex('cal_wall_handstand', 'Handstand an der Wand', 'calisthenics', 'body only', 'beginner',
   ['shoulders'], ['triceps', 'abdominals', 'traps'],
   ['Setz die Hände etwa eine Handlänge vor der Wand auf (Bauch zur Wand) oder schwing mit dem Rücken zur Wand hoch.',
    'Laufe mit den Füßen die Wand hoch, bis der Körper fast senkrecht ist.',
    'Drücke dich aktiv aus den Schultern raus, spanne Bauch und Gesäß an.',
    'Halte die Position und komm kontrolliert wieder runter.'],
   'w1', [F((60, FLOOR), **dict(t=275, hd=270, ua=270, la=270, th=85, sh=85)),
          F((60, FLOOR), **dict(t=273, hd=270, ua=270, la=270, th=86, sh=86))], [wall(66), floor], mode='t', speed=0.4)

ex('cal_handstand', 'Freier Handstand', 'calisthenics', 'body only', 'expert',
   ['shoulders'], ['triceps', 'abdominals', 'traps', 'forearms'],
   ['Setz die Hände schulterbreit auf und spreize die Finger.',
    'Schwing mit einem Bein hoch und bring beide Beine zusammen über die Hüfte.',
    'Balanciere über die Finger und Handballen, der Körper ist gestreckt.',
    'Halte die Position. Zum Abbrechen fällst du in ein Rad oder rollst ab.'],
   'w1', [F((50, FLOOR), **dict(t=270, hd=270, ua=270, la=270, th=90, sh=90)),
          F((50, FLOOR), **dict(t=271, hd=270, ua=271, la=270, th=89, sh=91))], [floor], mode='t', speed=0.5)

# ---------------------------------------------------------------- Front Lever
FL = dict(t=180, hd=180, ua=88, la=88, th=0, sh=0)
ex('cal_tuck_front_lever', 'Tuck Front Lever', 'calisthenics', 'pull-up bar', 'intermediate',
   ['lats'], ['abdominals', 'middle back', 'shoulders'],
   ['Hänge an der Stange und ziehe die Knie eng an die Brust.',
    'Drücke die Stange mit gestreckten Armen Richtung Hüfte, bis der Rücken waagerecht ist.',
    'Halte die Schulterblätter nach hinten-unten gezogen.',
    'Halte die Position für die vorgegebene Zeit.'],
   'w1', [F((50, 12), **dict(FL, th=40, sh=235)), F((50, 12), **dict(FL, t=182, th=42, sh=237))], [bar()], mode='t', speed=0.4)

ex('cal_adv_tuck_front_lever', 'Advanced Tuck Front Lever', 'calisthenics', 'pull-up bar', 'expert',
   ['lats'], ['abdominals', 'middle back', 'shoulders'],
   ['Wie der Tuck Front Lever, aber der Rücken ist flach und die Hüfte gestreckt.',
    'Die Oberschenkel bilden einen rechten Winkel zum Oberkörper.',
    'Halte die Arme gestreckt und den Rücken waagerecht.',
    'Halte die Position für die vorgegebene Zeit.'],
   'w1', [F((50, 12), **dict(FL, th=88, sh=0)), F((50, 12), **dict(FL, t=182, th=90, sh=2))], [bar()], mode='t', speed=0.4)

ex('cal_one_leg_front_lever', 'Front Lever einbeinig', 'calisthenics', 'pull-up bar', 'expert',
   ['lats'], ['abdominals', 'middle back', 'shoulders'],
   ['Gehe in den Advanced Tuck Front Lever.',
    'Strecke ein Bein komplett aus, das andere bleibt angewinkelt.',
    'Halte den Körper waagerecht und wechsle zwischen den Sätzen das Bein.',
    'Halte die Position für die vorgegebene Zeit.'],
   'w1', [F((50, 12), **dict(FL, th1=0, sh1=0, th2=88, sh2=0)),
          F((50, 12), **dict(FL, t=182, th1=2, sh1=2, th2=90, sh2=2))], [bar()], mode='t', speed=0.4)

ex('cal_straddle_front_lever', 'Straddle Front Lever', 'calisthenics', 'pull-up bar', 'expert',
   ['lats'], ['abdominals', 'middle back', 'shoulders', 'adductors'],
   ['Gehe aus dem Hang in die waagerechte Position.',
    'Die Beine sind gestreckt und weit gegrätscht, das verkürzt den Hebel.',
    'Arme gestreckt, Körper vollständig waagerecht.',
    'Halte die Position für die vorgegebene Zeit.'],
   'w1', [F((50, 12), **dict(FL, th2=355, sh2=355)), F((50, 12), **dict(FL, t=182, th2=357, sh2=357))], [bar()], mode='t', speed=0.4)

ex('cal_front_lever', 'Front Lever', 'calisthenics', 'pull-up bar', 'expert',
   ['lats'], ['abdominals', 'middle back', 'shoulders', 'lower back'],
   ['Hänge an der Stange mit schulterbreitem Obergriff.',
    'Drücke die Stange mit gestreckten Armen nach unten und hebe den gestreckten Körper an.',
    'Der ganze Körper ist waagerecht, das Gesicht zeigt nach oben.',
    'Halte die Position mit voller Körperspannung.'],
   'w1', [F((50, 12), **FL), F((50, 12), **dict(FL, t=182, th=2, sh=2))], [bar()], mode='t', speed=0.4)

ex('cal_front_lever_raise', 'Front Lever Raises', 'calisthenics', 'pull-up bar', 'expert',
   ['lats'], ['abdominals', 'shoulders'],
   ['Hänge an der Stange mit gestreckten Armen.',
    'Hebe den gestreckten (oder gehockten) Körper bis in die Waagerechte oder darüber.',
    'Senke ihn langsam wieder ab, ohne zu schwingen.',
    'Wiederhole die Bewegung kontrolliert.'],
   'w1', [F((50, 12), **HANG), F((50, 12), **FL)], [bar()], speed=0.5)

# ---------------------------------------------------------------- Back Lever
BL = dict(t=0, hd=0, ua=100, la=100, th=180, sh=180)
ex('cal_german_hang', 'German Hang', 'calisthenics', 'pull-up bar', 'intermediate',
   ['shoulders'], ['biceps', 'chest'],
   ['Hänge an der Stange (am besten an Ringen oder einer niedrigen Stange).',
    'Ziehe die Knie an und rolle rückwärts durch die Arme (Skin the Cat).',
    'Lass die Füße Richtung Boden sinken, bis du eine Dehnung in Schultern und Brust spürst.',
    'Halte kurz und rolle kontrolliert zurück.'],
   'w1', [F((50, 12), **dict(t=255, hd=255, ua=120, la=120, th=300, sh=270)),
          F((50, 12), **dict(t=250, hd=250, ua=118, la=118, th=295, sh=270))], [bar()], mode='t', speed=0.4)

ex('cal_tuck_back_lever', 'Tuck Back Lever', 'calisthenics', 'pull-up bar', 'intermediate',
   ['shoulders', 'lats'], ['chest', 'biceps', 'abdominals'],
   ['Rolle rückwärts durch die Arme in den Hang (wie beim German Hang).',
    'Bringe den Rücken in die Waagerechte, die Knie sind eng an der Brust.',
    'Die Arme bleiben gestreckt.',
    'Halte die Position für die vorgegebene Zeit.'],
   'w1', [F((50, 12), **dict(BL, th=320, sh=135)), F((50, 12), **dict(BL, t=2, th=322, sh=137))], [bar()], mode='t', speed=0.4)

ex('cal_straddle_back_lever', 'Straddle Back Lever', 'calisthenics', 'pull-up bar', 'expert',
   ['shoulders', 'lats'], ['chest', 'biceps', 'abdominals', 'lower back'],
   ['Gehe in den Tuck Back Lever.',
    'Strecke die Beine gegrätscht nach hinten aus.',
    'Der Körper ist waagerecht, das Gesicht zeigt nach unten.',
    'Halte die Position für die vorgegebene Zeit.'],
   'w1', [F((50, 12), **dict(BL, th2=185, sh2=185)), F((50, 12), **dict(BL, t=2, th2=187, sh2=187))], [bar()], mode='t', speed=0.4)

ex('cal_back_lever', 'Back Lever', 'calisthenics', 'pull-up bar', 'expert',
   ['shoulders', 'lats'], ['chest', 'biceps', 'abdominals', 'lower back', 'glutes'],
   ['Rolle rückwärts in den Hang und strecke den Körper.',
    'Senke den gestreckten Körper ab, bis er waagerecht ist, das Gesicht zeigt nach unten.',
    'Die Arme bleiben gestreckt, Gesäß und Bauch sind angespannt.',
    'Halte die Position für die vorgegebene Zeit.'],
   'w1', [F((50, 12), **BL), F((50, 12), **dict(BL, t=2, th=182, sh=182))], [bar()], mode='t', speed=0.4)

# ---------------------------------------------------------------- Planche
PL = dict(t=0, hd=355, ua=255, la=255, th=180, sh=180)
ex('cal_tuck_planche', 'Tuck Planche', 'calisthenics', 'parallettes', 'expert',
   ['shoulders'], ['chest', 'triceps', 'abdominals', 'forearms'],
   ['Hocke dich hin und setz die Hände neben der Hüfte auf (gern auf Parallettes).',
    'Lehne dich weit nach vorne, bis die Füße abheben. Die Knie bleiben an der Brust.',
    'Die Arme sind komplett gestreckt, der Rücken ist leicht rund.',
    'Halte die Position für die vorgegebene Zeit.'],
   'w1', [F((55, FLOOR), **dict(PL, t=10, th=330, sh=165)), F((55, FLOOR), **dict(PL, t=12, th=332, sh=167))], [floor], mode='t', speed=0.4)

ex('cal_adv_tuck_planche', 'Advanced Tuck Planche', 'calisthenics', 'parallettes', 'expert',
   ['shoulders'], ['chest', 'triceps', 'abdominals', 'lower back'],
   ['Gehe in die Tuck Planche.',
    'Strecke den Rücken flach und schiebe die Hüfte nach hinten auf Schulterhöhe.',
    'Die Knie bleiben angewinkelt, die Oberschenkel zeigen nach unten.',
    'Halte die Position für die vorgegebene Zeit.'],
   'w1', [F((55, FLOOR), **dict(PL, th=270, sh=180)), F((55, FLOOR), **dict(PL, t=2, th=272, sh=182))], [floor], mode='t', speed=0.4)

ex('cal_straddle_planche', 'Straddle Planche', 'calisthenics', 'parallettes', 'expert',
   ['shoulders'], ['chest', 'triceps', 'abdominals', 'lower back', 'glutes'],
   ['Gehe in die Advanced Tuck Planche.',
    'Strecke die Beine gegrätscht nach hinten aus.',
    'Der Körper ist waagerecht, die Arme sind gestreckt.',
    'Halte die Position für die vorgegebene Zeit.'],
   'w1', [F((55, FLOOR), **dict(PL, th2=175, sh2=175)), F((55, FLOOR), **dict(PL, t=2, th2=177, sh2=177))], [floor], mode='t', speed=0.4)

ex('cal_full_planche', 'Planche', 'calisthenics', 'parallettes', 'expert',
   ['shoulders'], ['chest', 'triceps', 'abdominals', 'lower back', 'glutes'],
   ['Stütze dich auf gestreckten Armen, die Hände ungefähr auf Hüfthöhe.',
    'Lehne dich weit nach vorne und hebe die geschlossenen, gestreckten Beine an.',
    'Der gesamte Körper ist waagerecht über dem Boden.',
    'Halte die Position mit maximaler Körperspannung.'],
   'w1', [F((55, FLOOR), **PL), F((55, FLOOR), **dict(PL, t=2, th=182, sh=182))], [floor], mode='t', speed=0.4)

# ---------------------------------------------------------------- L-Sit / Core
LS = dict(t=92, ua=268, la=268, th=0, sh=0)
ex('cal_tuck_lsit', 'Tuck L-Sit', 'calisthenics', 'parallettes', 'beginner',
   ['abdominals'], ['triceps', 'shoulders'],
   ['Setz dich zwischen zwei Parallettes oder Stühle und stütze dich mit gestreckten Armen.',
    'Hebe das Gesäß an und ziehe die Knie zur Brust.',
    'Drücke die Schultern nach unten.',
    'Halte die Position für die vorgegebene Zeit.'],
   'w1', [F((50, 78), **dict(LS, th=40, sh=270)), F((50, 78), **dict(LS, th=42, sh=272))],
   [box(44, 78, 12, 10), floor], mode='t', speed=0.4)

ex('cal_one_leg_lsit', 'L-Sit einbeinig', 'calisthenics', 'parallettes', 'intermediate',
   ['abdominals'], ['triceps', 'shoulders', 'quadriceps'],
   ['Gehe in den Tuck L-Sit.',
    'Strecke ein Bein gerade nach vorne, das andere bleibt angezogen.',
    'Wechsle das Bein nach jedem Satz.',
    'Halte die Position für die vorgegebene Zeit.'],
   'w1', [F((50, 78), **dict(LS, th2=40, sh2=270)), F((50, 78), **dict(LS, th1=2, sh1=2, th2=42, sh2=272))],
   [box(44, 78, 12, 10), floor], mode='t', speed=0.4)

ex('cal_lsit', 'L-Sit', 'calisthenics', 'parallettes', 'intermediate',
   ['abdominals'], ['triceps', 'shoulders', 'quadriceps', 'hip flexors'],
   ['Stütze dich auf Parallettes, am Barren oder am Boden.',
    'Hebe die gestreckten, geschlossenen Beine an, bis sie parallel zum Boden sind.',
    'Drücke die Schultern nach unten und strecke die Arme.',
    'Halte die Position für die vorgegebene Zeit.'],
   'w1', [F((50, 78), **LS), F((50, 78), **dict(LS, th=2, sh=2))], [box(44, 78, 12, 10), floor], mode='t', speed=0.4)

ex('cal_vsit', 'V-Sit', 'calisthenics', 'parallettes', 'expert',
   ['abdominals'], ['triceps', 'shoulders', 'hip flexors'],
   ['Gehe in den L-Sit.',
    'Lehne den Oberkörper leicht zurück und hebe die Beine weiter Richtung Gesicht.',
    'Die Arme sind gestreckt, die Hüfte schiebt nach vorne.',
    'Halte die Position für die vorgegebene Zeit.'],
   'w1', [F((50, 78), **dict(t=110, ua=275, la=275, th=50, sh=50)), F((50, 78), **dict(t=112, ua=276, la=276, th=52, sh=52))],
   [box(44, 78, 12, 10), floor], mode='t', speed=0.4)

ex('cal_hollow_hold', 'Hollow Body Hold', 'calisthenics', 'body only', 'beginner',
   ['abdominals'], ['hip flexors'],
   ['Leg dich auf den Rücken und drücke den unteren Rücken fest in den Boden.',
    'Hebe Schultern und gestreckte Beine leicht vom Boden ab.',
    'Strecke die Arme über den Kopf nach hinten.',
    'Halte die Bananenform. Wenn der Rücken abhebt, die Beine höher nehmen.'],
   'hip', [F((50, 84), **dict(t=165, hd=165, ua=172, la=172, th=12, sh=12)),
           F((50, 84), **dict(t=163, hd=163, ua=170, la=170, th=14, sh=14))], [floor], mode='t', speed=0.4)

ex('cal_hanging_knee_raise', 'Hängendes Knieheben', 'calisthenics', 'pull-up bar', 'beginner',
   ['abdominals'], ['hip flexors', 'forearms'],
   ['Hänge mit gestreckten Armen an der Stange.',
    'Ziehe die Knie kontrolliert bis über Hüfthöhe zur Brust.',
    'Senke die Beine langsam ab, ohne zu schwingen.',
    'Wiederhole die Bewegung.'],
   'w1', [F((50, 12), **HANG), F((50, 12), **dict(HANG, t=95, th=15, sh=270))], [bar()])

ex('cal_toes_to_bar', 'Toes to Bar', 'calisthenics', 'pull-up bar', 'intermediate',
   ['abdominals'], ['lats', 'hip flexors', 'forearms'],
   ['Hänge mit gestreckten Armen an der Stange.',
    'Hebe die gestreckten Beine, bis die Zehen die Stange berühren.',
    'Drücke die Stange dabei leicht nach unten.',
    'Senke die Beine kontrolliert ab.'],
   'w1', [F((50, 12), **HANG), F((50, 12), **dict(t=125, ua=75, la=75, th=70, sh=70))], [bar()], speed=0.7)

ex('cal_dragon_flag', 'Dragon Flag', 'calisthenics', 'bench', 'expert',
   ['abdominals'], ['lower back', 'lats', 'glutes'],
   ['Leg dich auf eine Bank und greife hinter dem Kopf an die Bank.',
    'Hebe den gestreckten Körper an, bis nur noch die oberen Schultern aufliegen.',
    'Senke den geraden Körper langsam ab, ohne in der Hüfte abzuknicken.',
    'Kurz vor der Bank stoppen und wieder hochheben.'],
   'sh', [F((28, 72), **dict(t=240, hd=180, ua=180, la=100, th=60, sh=60)),
          F((28, 72), **dict(t=200, hd=180, ua=180, la=100, th=20, sh=20))], [box(10, 74, 60, 6), floor], speed=0.5)

# ---------------------------------------------------------------- Beine
ex('cal_assisted_pistol', 'Pistol Squat mit Hilfe', 'calisthenics', 'body only', 'beginner',
   ['quadriceps'], ['glutes', 'hamstrings', 'calves'],
   ['Stell dich auf ein Bein und halte dich an einer Tür, Stange oder einem Band fest.',
    'Strecke das andere Bein nach vorne.',
    'Geh auf einem Bein so tief wie möglich in die Hocke.',
    'Drücke dich wieder hoch, nutze die Arme nur so viel wie nötig.'],
   'f1', [F((45, FLOOR), **dict(t=88, ua=0, la=0, th1=270, sh1=270, th2=330, sh2=330)),
          F((45, FLOOR), **dict(t=65, ua=10, la=10, th1=355, sh1=242, th2=5, sh2=5))], [wall(80), floor], speed=0.7)

ex('cal_box_pistol', 'Pistol Squat auf Box', 'calisthenics', 'body only', 'intermediate',
   ['quadriceps'], ['glutes', 'hamstrings'],
   ['Stell dich mit dem Rücken vor eine Bank oder Box.',
    'Strecke ein Bein nach vorne und setze dich einbeinig langsam auf die Box.',
    'Steh ohne Schwung wieder auf.',
    'Mit der Zeit nimmst du eine niedrigere Box.'],
   'f1', [F((50, FLOOR), **dict(t=88, ua=0, la=0, th1=270, sh1=270, th2=330, sh2=330)),
          F((50, FLOOR), **dict(t=70, ua=0, la=0, th1=0, sh1=255, th2=10, sh2=10))], [box(20, 70, 18, 18), floor], speed=0.7)

ex('cal_pistol_squat', 'Pistol Squat', 'calisthenics', 'body only', 'expert',
   ['quadriceps'], ['glutes', 'hamstrings', 'calves', 'abdominals'],
   ['Stell dich auf ein Bein, das andere Bein ist gestreckt vor dir.',
    'Strecke die Arme zum Ausgleich nach vorne.',
    'Geh auf einem Bein komplett in die Hocke, die Ferse bleibt am Boden.',
    'Drücke dich ohne Hilfe wieder hoch.'],
   'f1', [F((45, FLOOR), **dict(t=88, ua=0, la=0, th1=270, sh1=270, th2=330, sh2=330)),
          F((45, FLOOR), **dict(t=60, ua=5, la=5, th1=355, sh1=242, th2=5, sh2=5))], [floor], speed=0.7)

ex('cal_shrimp_squat', 'Shrimp Squat', 'calisthenics', 'body only', 'expert',
   ['quadriceps'], ['glutes', 'hamstrings'],
   ['Stell dich auf ein Bein und greife den anderen Fuß hinter dem Körper.',
    'Senke dich auf dem Standbein ab, bis das hintere Knie den Boden berührt.',
    'Halte den Oberkörper leicht nach vorne geneigt.',
    'Drücke dich wieder hoch.'],
   'f1', [F((50, FLOOR), **dict(t=85, ua1=0, la1=0, ua2=250, la2=290, th1=270, sh1=270, th2=250, sh2=110)),
          F((50, FLOOR), **dict(t=65, ua1=0, la1=0, ua2=230, la2=300, th1=345, sh1=240, th2=240, sh2=150))], [floor], speed=0.7)

ex('cal_wall_sit', 'Wandsitzen (Wall Sit)', 'calisthenics', 'body only', 'beginner',
   ['quadriceps'], ['glutes', 'calves'],
   ['Lehne dich mit dem Rücken an eine Wand.',
    'Rutsche nach unten, bis Knie und Hüfte etwa 90 Grad gebeugt sind.',
    'Die Knie sind über den Fußgelenken.',
    'Halte die Position für die vorgegebene Zeit.'],
   'f1', [F((48, FLOOR), **dict(t=90, ua=280, la=0, th=0, sh=270)),
          F((48, FLOOR), **dict(t=90, ua=280, la=2, th=1, sh=270))], [wall(30), floor], mode='t', speed=0.4)

ex('cal_single_calf_raise', 'Einbeiniges Wadenheben', 'calisthenics', 'body only', 'beginner',
   ['calves'], [],
   ['Stell dich auf einem Bein auf eine Treppenstufe, die Ferse hängt über die Kante.',
    'Halte dich zum Gleichgewicht leicht fest.',
    'Drücke dich so hoch wie möglich auf die Zehenspitzen.',
    'Senke die Ferse langsam unter die Stufe ab.'],
   'f1', [F((50, 78), **dict(t=90, ua=0, la=0, th1=270, sh1=270, th2=270, sh2=200)),
          F((50, 70), **dict(t=90, ua=0, la=0, th1=270, sh1=270, th2=270, sh2=200))], [box(40, 78, 20, 10), floor])

# ---------------------------------------------------------------- Kondition
ex('cal_burpee', 'Burpee', 'cardio', 'body only', 'beginner',
   ['quadriceps'], ['chest', 'shoulders', 'triceps', 'abdominals', 'calves'],
   ['Steh aufrecht mit hüftbreitem Stand.',
    'Geh in die Hocke, setz die Hände auf und spring mit den Füßen in den Liegestütz.',
    'Optional: mach einen Liegestütz.',
    'Spring mit den Füßen zurück zu den Händen und spring explosiv mit den Armen über dem Kopf hoch.'],
   'f1', [F((40, FLOOR), **STAND),
          F((40, FLOOR), **dict(t=50, ua=280, la=280, th=10, sh=240)),
          F((15, FLOOR), **PUSH_TOP),
          F((40, FLOOR), **dict(t=50, ua=280, la=280, th=10, sh=240)),
          F((40, 78), **dict(t=90, ua=90, la=90, th=270, sh=270))], [floor], loop='cycle', speed=0.8)

ex('cal_jumping_jack', 'Hampelmann (Jumping Jacks)', 'cardio', 'body only', 'beginner',
   ['calves'], ['shoulders', 'quadriceps'],
   ['Steh aufrecht, die Arme hängen seitlich am Körper.',
    'Spring in die Grätsche und führe die Arme seitlich über den Kopf.',
    'Spring zurück in die Ausgangsposition.',
    'Wiederhole die Bewegung in einem flüssigen Rhythmus.'],
   'hip', [F((50, 52), **dict(t=90, ua1=262, la1=262, ua2=278, la2=278, th1=268, sh1=268, th2=272, sh2=272)),
           F((50, 50), **dict(t=90, ua1=115, la1=105, ua2=65, la2=75, th1=250, sh1=250, th2=290, sh2=290))],
   [floor], speed=1.6)

ex('cal_high_knees', 'Kniehebelauf (High Knees)', 'cardio', 'body only', 'beginner',
   ['quadriceps'], ['calves', 'abdominals', 'hip flexors'],
   ['Lauf auf der Stelle.',
    'Ziehe die Knie abwechselnd bis auf Hüfthöhe hoch.',
    'Die Arme schwingen aktiv mit.',
    'Bleib auf den Fußballen und halte ein hohes Tempo.'],
   'hip', [F((50, 52), **dict(t=92, ua1=300, la1=40, ua2=230, la2=280, th1=0, sh1=270, th2=268, sh2=268)),
           F((50, 52), **dict(t=92, ua1=230, la1=280, ua2=300, la2=40, th1=268, sh1=268, th2=0, sh2=270))],
   [floor], speed=1.8)

ex('cal_bear_crawl', 'Bärengang (Bear Crawl)', 'cardio', 'body only', 'beginner',
   ['shoulders'], ['quadriceps', 'abdominals', 'triceps'],
   ['Geh in den Vierfüßlerstand und hebe die Knie wenige Zentimeter vom Boden.',
    'Bewege dich vorwärts, indem du gleichzeitig die gegenüberliegende Hand und den Fuß versetzt.',
    'Halte den Rücken flach und die Hüfte tief.',
    'Laufe eine Strecke oder eine bestimmte Zeit.'],
   'hip', [F((45, 62), **dict(t=5, ua1=255, la1=265, ua2=275, la2=280, th1=310, sh1=235, th2=290, sh2=220)),
           F((45, 62), **dict(t=5, ua1=275, la1=280, ua2=255, la2=265, th1=290, sh1=220, th2=310, sh2=235))],
   [floor], speed=1.2)

# ---------------------------------------------------------------- Human Flag
ex('cal_tuck_human_flag', 'Tuck Human Flag', 'calisthenics', 'other', 'expert',
   ['abdominals', 'lats'], ['shoulders', 'obliques', 'triceps'],
   ['Greife eine senkrechte Stange: die obere Hand im Obergriff, die untere im Untergriff, etwas mehr als schulterbreit.',
    'Drücke mit dem unteren Arm und ziehe mit dem oberen Arm.',
    'Hebe die Beine mit angezogenen Knien zur Seite an, bis die Hüfte auf Schulterhöhe ist.',
    'Halte die Position für die vorgegebene Zeit.'],
   'w1', [F((30, 22), **dict(t=200, hd=200, ua1=120, la1=110, ua2=230, la2=230, th=40, sh=320)),
          F((30, 22), **dict(t=198, hd=198, ua1=118, la1=110, ua2=232, la2=232, th=42, sh=322))],
   [pole(30), floor], mode='t', speed=0.4)

ex('cal_human_flag', 'Human Flag', 'calisthenics', 'other', 'expert',
   ['abdominals', 'lats'], ['shoulders', 'obliques', 'triceps'],
   ['Greife eine senkrechte Stange, die Hände etwas mehr als schulterbreit.',
    'Drücke mit dem unteren Arm, ziehe mit dem oberen Arm.',
    'Hebe den gestreckten Körper seitlich an, bis er waagerecht wie eine Fahne ist.',
    'Halte die Position mit voller Körperspannung.'],
   'w1', [F((30, 22), **dict(t=200, hd=200, ua1=120, la1=110, ua2=230, la2=230, th=0, sh=0)),
          F((30, 22), **dict(t=198, hd=198, ua1=118, la1=110, ua2=232, la2=232, th=2, sh=2))],
   [pole(30), floor], mode='t', speed=0.4)
