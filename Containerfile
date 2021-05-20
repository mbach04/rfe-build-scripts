FROM registry.redhat.io/rhel8/httpd-24

ADD kickstart.ks /var/www/html/

ARG commit=8de1408b-ce61-42ed-aab3-4f1bfa56f642-commit.tar

ADD $commit /var/www/html/

CMD run-httpd
