#!/usr/bin/env python

import requests
import sys


def main(phone, msg):
    url = "http://10.30.154.108:1128/v1.0/sms"
    data = msg.split('|')
    type = data[0]
    # sms = data[1].split('__')[0] + data[2]
    sms = data[1] + data[2]
    sms = sms.replace("'","")
    # srv = data[1].split('__')[1]
    # own = data[1].split('__')[2]
    hos = data[3]
    dat = data[4]
    alert = '|TYP: ' + type.upper() + '\n'\
    + '|MSG: ' + '- ' + sms.lower() + '\n'\
    + '|HOS: ' + hos.upper() + '\n'\
    # + 'SRV: ' + srv.upper() + '\n'\
    # + 'OWN: ' + own.upper() + '\n'\
    + '|TIME: ' + dat + '|AUTH: huanpc'

    payload = {"mobile": phone, "sms": alert}
    # Send SMS
    r = requests.post(url, json=payload, auth=('system','nfdlLL12_32**'))
    print r.status_code

def help():
    print 'Usage: python ' +sys.argv[0]+ ' $CONTACTEMAIL$ $NOTIFICATIONTYPE$ $SERVICEDESC$ $SERVICEOUTPUT$ $HOSTADDRESS$ $SHORTDATETIME$'

if __name__ == "__main__":
    if len(sys.argv) != 3:
        help()
    else:
        phone = '+' + str(sys.argv[1])
        msg = sys.argv[2]
        main(phone, msg)
