"""使用临时数据库验证账号隔离、版本冲突和模型未配置时的反馈。"""

import importlib.util
import hashlib
import json
import os
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path


spec = importlib.util.spec_from_file_location('richeng_server', Path(__file__).with_name('server.py'))
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


class ServiceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = tempfile.TemporaryDirectory()
        server.DB = Path(cls.folder.name) / 'test.sqlite3'
        server.initialize()
        cls.http = server.ThreadingHTTPServer(('127.0.0.1', 0), server.Handler)
        cls.thread = threading.Thread(target=cls.http.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f'http://127.0.0.1:{cls.http.server_port}'

    @classmethod
    def tearDownClass(cls):
        cls.http.shutdown()
        cls.http.server_close()
        cls.thread.join()
        cls.folder.cleanup()

    def request(self, path, data=None, token=None):
        headers = {'Content-Type': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer ' + token
        request = urllib.request.Request(self.base + path, data=None if data is None else json.dumps(data).encode(), headers=headers)
        try:
            with urllib.request.urlopen(request) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as error:
            with error:
                return error.code, json.load(error)

    def test_account_isolation_and_conflict(self):
        status, first = self.request('/api/register', {'email': 'first@example.test', 'password': 'test-only-password'})
        self.assertEqual(status, 200)
        _, second = self.request('/api/register', {'email': 'second@example.test', 'password': 'test-only-password'})
        self.assertEqual(self.request('/api/sync')[0], 401)
        data = [{'id': 'p1', 'title': '测试项目', 'phases': [{'id': 's1', 'title': '准备', 'tasks': [{'id': 't1', 'title': '资料整理', 'status': 'done', 'difficulty': 1}]}]}]
        self.assertEqual(self.request('/api/sync', {'revision': 0, 'projects': data}, first['token'])[0], 200)
        status, remote = self.request('/api/sync', token=first['token'])
        self.assertEqual(remote['projects'], data)
        self.assertEqual(remote['revision'], 1)
        self.assertEqual(self.request('/api/sync', {'revision': 0, 'projects': []}, first['token'])[0], 409)
        self.assertEqual(self.request('/api/sync', token=second['token'])[1]['projects'], [])
        self.assertEqual(self.request('/api/login', {'email': 'first@example.test', 'password': 'wrong-password'})[0], 401)
        self.assertEqual(self.request('/api/logout', {}, first['token'])[0], 200)
        self.assertEqual(self.request('/api/sync', token=first['token'])[0], 401)

    def test_invalid_data_rejected(self):
        _, account = self.request('/api/register', {'email': 'invalid@example.test', 'password': 'test-only-password'})
        self.assertEqual(self.request('/api/sync', {'revision': 0, 'projects': [{'title': '缺少标识'}]}, account['token'])[0], 400)
        self.assertEqual(self.request('/api/sync', token=account['token'])[1]['revision'], 0)

    def test_standard_email_providers_are_supported(self):
        # 服务端仅校验标准邮箱格式，不限制 QQ、163、Gmail、Outlook 或企业邮箱。
        for email in ('person+plan@gmail.com', 'member@outlook.com', 'staff@example.org'):
            status, account = self.request(
                '/api/register', {'email': email, 'password': 'test-only-password'},
            )
            self.assertEqual(status, 200)
            self.assertEqual(account['email'], email)

    def test_schedule_fields_are_validated(self):
        _, account = self.request('/api/register', {'email': 'schedule@example.test', 'password': 'test-only-password'})
        task = {
            'id': 'task-1', 'title': '安排会议', 'status': 'todo', 'difficulty': 1,
            'scheduled': '2026-09-15', 'scheduleDates': ['2026-09-15', '2026-09-17'], 'scheduledTime': '09:30',
            'deadline': None, 'estimatedMinutes': 60, 'reminderMinutes': 15,
        }
        data = [{'id': 'project-1', 'title': '项目', 'phases': [{'id': 'phase-1', 'title': '阶段', 'tasks': [task]}]}]
        self.assertEqual(self.request('/api/sync', {'revision': 0, 'projects': data}, account['token'])[0], 200)
        task['scheduledTime'] = '25:00'
        self.assertEqual(self.request('/api/sync', {'revision': 1, 'projects': data}, account['token'])[0], 400)

    def test_can_list_and_remove_other_device(self):
        _, first = self.request(
            '/api/register',
            {'email': 'devices@example.test', 'password': 'test-only-password', 'device': 'Windows'},
        )
        _, second = self.request(
            '/api/login',
            {'email': 'devices@example.test', 'password': 'test-only-password', 'device': 'Android'},
        )
        _, response = self.request('/api/devices', token=first['token'])
        other = next(item for item in response['devices'] if not item['current'])
        self.assertEqual(other['name'], 'Android')
        self.assertEqual(
            self.request('/api/devices/revoke', {'id': other['id']}, first['token'])[0],
            200,
        )
        self.assertEqual(self.request('/api/sync', token=second['token'])[0], 401)

    def test_registration_can_require_one_time_email_code(self):
        previous = os.environ.get('EMAIL_VERIFICATION_REQUIRED')
        os.environ['EMAIL_VERIFICATION_REQUIRED'] = '1'
        email, code = 'verified@example.test', '123456'
        try:
            with server.database() as conn:
                conn.execute(
                    'INSERT INTO email_codes(email,code,expires,attempts,sent_at) VALUES (?,?,?,?,?)',
                    (email, hashlib.sha256(f'{email}:{code}'.encode()).hexdigest(), 9_999_999_999, 0, 0),
                )
            status, account = self.request(
                '/api/register',
                {'email': email, 'password': 'test-only-password', 'code': code},
            )
            self.assertEqual(status, 200)
            self.assertIn('token', account)
            self.assertEqual(
                self.request(
                    '/api/register',
                    {'email': 'bad-code@example.test', 'password': 'test-only-password', 'code': '123456'},
                )[0],
                400,
            )
        finally:
            if previous is None:
                os.environ.pop('EMAIL_VERIFICATION_REQUIRED', None)
            else:
                os.environ['EMAIL_VERIFICATION_REQUIRED'] = previous


if __name__ == '__main__':
    unittest.main()
