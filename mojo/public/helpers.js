const addFormManager = {
  showAdd: function (event) {
    toggleModal(event);
    document.getElementById('add_name').focus();
  },
  submitForm: function (event) {
    document.getElementById('addForm').submit();
  }
};

const editFormManager = {
  showEdit: function (event, json) {
    let data = JSON.parse(json);
    document.getElementById('mac').value = data.mac;
    document.getElementById('edit_name').value = data.name;
    document.getElementById('edit_mac').value = data.mac;
    document.getElementById('edit_ip').value = data.ip;

    toggleModal(event);
    document.getElementById('edit_name').focus();
  },
  submitForm: function (event) {
    document.getElementById('editForm').submit();
  },
  deleteForm: function (event) {
    let mac = document.getElementById('mac').value;
    if (mac) {
      document.getElementById('delete_mac').value = mac;
      document.getElementById('deleteForm').submit();
    }
  }
};

const pingHandler = {
  ws: null,
  toSend: [],

  _send: function (obj) {
    let json = JSON.stringify(obj);
    if (this.ws) {
      if (this.ws.readyState == WebSocket.OPEN || this.ws.readyState == WebSocket.CONNECTING) {
        this.ws.send(json);
        return;
      }
      else {
        this.ws.close(1000, "reconnecting");
      }
    }
    this.toSend.push(json); // send after connection
    this.start();
  },

  pingIP: function (ip, tries = 1) {
    this.setProgress(ip, 1);
    this._send({cmd: "ping", ip: ip, tries: tries});
  },

  pingAll: function () {
    this._send({cmd: "pingAll"});
  },

  start: function () {
    this.ws = new WebSocket('/ws');
    this.ws.onmessage = this.handleMessage.bind(this);
    this.ws.onopen = this.handleOpen.bind(this);
  },

  handleOpen: function (event) {
    let e;
    while ((e = this.toSend.shift())) {
      this.ws.send(e);
    }
  },

  handleMessage: function (event) {
    const data = JSON.parse(event.data);

    if (data.ip) {
      const awakeDiv = document.getElementById(`awake_${data.ip}`);
      const asleepDiv = document.getElementById(`asleep_${data.ip}`);
      if (awakeDiv && asleepDiv) {
        if (data.status === 'awake') {
          asleepDiv.style.display = 'none';
          awakeDiv.style.display = 'inline-block';
        } else {
          asleepDiv.style.display = 'inline-block';
          awakeDiv.style.display = 'none';
        }
      }

      this.setProgress(data.ip, 0);
    }
  },

  isAsleep: function (ip) {
    const awakeDiv = document.getElementById(`awake_${ip}`);
    if (awakeDiv && awakeDiv.style.display === 'none') {
      return 1;
    }
    return 0;
  },

  isAwake: function (ip) {
    return !this.isAsleep(ip);
  },

  setProgress: function(ip, active) {
    // TODO: this looks ugly
    return;

    const progressDiv = document.getElementById(`progress_${ip}`);
    if (progressDiv) {
      progressDiv.style.display = active ? 'inline-block' : 'none';
    }
  }
};

document.addEventListener('DOMContentLoaded', () => {
  if (window.location.pathname === '/add') {
    // Add host but there were errors
    const fakeEvent = {
      preventDefault: () => {},
      currentTarget: document.querySelector('a[data-target="modal-add"]')
    };
    toggleModal(fakeEvent);

    const element = document.querySelector('.field-with-error');
    if (element) {
      element.focus();
    }
  }
  else if (window.location.pathname === '/edit') {
    // edit form but there were errors
    const fakeEvent = {
      preventDefault: () => {},
      currentTarget: document.querySelector('a[data-target="modal-edit"]')
    };
    toggleModal(fakeEvent);

    const element = document.querySelector('.field-with-error');
    if (element) {
      element.focus();
    }
  }

  if (arisen) {
    // if we just tried to wake a host, ping it for longer
    console.log("checking on newly arisen host " + arisen);
    pingHandler.pingIP(arisen, 5);
  }
  else {
    // otherwise, ping all
    pingHandler.pingAll();
  }
});

