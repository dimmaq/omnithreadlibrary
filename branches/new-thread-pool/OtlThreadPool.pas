///<summary>Thread pool implementation. Part of the OmniThreadLibrary project.</summary>
///<author>Primoz Gabrijelcic</author>
///<license>
///This software is distributed under the BSD license.
///
///Copyright (c) 2008-2009, Primoz Gabrijelcic
///All rights reserved.
///
///Redistribution and use in source and binary forms, with or without modification,
///are permitted provided that the following conditions are met:
///- Redistributions of source code must retain the above copyright notice, this
///  list of conditions and the following disclaimer.
///- Redistributions in binary form must reproduce the above copyright notice,
///  this list of conditions and the following disclaimer in the documentation
///  and/or other materials provided with the distribution.
///- The name of the Primoz Gabrijelcic may not be used to endorse or promote
///  products derived from this software without specific prior written permission.
///
///THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
///ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
///WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
///DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
///ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
///(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
///LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
///ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
///(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
///SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
///</license>
///<remarks><para>
///   Home              : http://otl.17slon.com
///   Support           : http://otl.17slon.com/forum/
///   Author            : Primoz Gabrijelcic
///     E-Mail          : primoz@gabrijelcic.org
///     Blog            : http://thedelphigeek.com
///     Web             : http://gp.17slon.com
///   Contributors      : GJ, Lee_Nover
///
///   Creation date     : 2008-06-12
///   Last modification : 2008-08-26
///   Version           : 1.0
///</para><para>
///   History:
///     1.0: 2008-08-26
///       - First official release.
///</para></remarks>

/// WARNING Tasks must be scheduled from the owner thread! WARNING
/// (access to task queues is not synchronised)

unit OtlThreadPool;

interface

{ TODO 1 -oPrimoz Gabrijelcic : Rewrite using one ITaskControl to manage thread pool. }
{ TODO 1 -oPrimoz Gabrijelcic : Use OtlCommunication to send messages to the Monitor. }

// TODO 1 -oPrimoz Gabrijelcic : Should be monitorable by the OmniTaskEventDispatch
// TODO 3 -oPrimoz Gabrijelcic : Needs an async event reporting unexpected states (kill threads, for example)

uses
  Windows,
  SysUtils,
  OtlTask;

const
  CDefaultIdleWorkerThreadTimeout_sec = 10;
  CDefaultWaitOnTerminate_sec         = 30;

type
  IOmniThreadPool = interface;

  IOmniThreadPoolMonitor = interface ['{09EFADE8-3F14-4184-87CA-131100EC57E4}']
    function  Detach(const task: IOmniThreadPool): IOmniThreadPool;
    function  Monitor(const task: IOmniThreadPool): IOmniThreadPool;
  end; { IOmniThreadPoolMonitor }

  TThreadPoolOperation = (tpoCreateThread, tpoDestroyThread, tpoKillThread,
    tpoWorkItemCompleted);

  TOmniThreadPoolMonitorInfo = class
  strict private
    otpmiTaskID             : int64;
    otpmiThreadID           : integer;
    otpmiThreadPoolOperation: TThreadPoolOperation;
    otpmiUniqueID           : int64;
  public
    constructor Create(uniqueID: int64; threadPoolOperation: TThreadPoolOperation; threadID:
      integer); overload;
    constructor Create(uniqueID, taskID: int64); overload;
    property TaskID: int64 read otpmiTaskID;
    property ThreadPoolOperation: TThreadPoolOperation read otpmiThreadPoolOperation;
    property ThreadID: integer read otpmiThreadID;
    property UniqueID: int64 read otpmiUniqueID;
  end; { TOmniThreadPoolMonitorInfo }

  ///<summary>Worker thread lifetime reporting handler.</summary>
  TOTPWorkerThreadEvent = procedure(Sender: TObject; threadID: DWORD) of object;

  IOmniThreadPool = interface ['{1FA74554-1866-46DD-AC50-F0403E378682}']
    function  GetIdleWorkerThreadTimeout_sec: integer;
    function  GetMaxExecuting: integer;
    function  GetMaxQueued: integer;
    function  GetMaxQueuedTime_sec: integer;
    function  GetMinWorkers: integer;
    function  GetName: string;
    function  GetOnWorkerThreadCreated_Asy: TOTPWorkerThreadEvent;
    function  GetOnWorkerThreadDestroying_Asy: TOTPWorkerThreadEvent;
    function  GetUniqueID: int64;
    function  GetWaitOnTerminate_sec: integer;
    procedure SetIdleWorkerThreadTimeout_sec(value: integer);
    procedure SetMaxExecuting(value: integer);
    procedure SetMaxQueued(value: integer);
    procedure SetMaxQueuedTime_sec(value: integer);
    procedure SetMinWorkers(value: integer);
    procedure SetName(const value: string);
    procedure SetWaitOnTerminate_sec(value: integer);
    procedure SetOnWorkerThreadCreated_Asy(const value: TOTPWorkerThreadEvent);
    procedure SetOnWorkerThreadDestroying_Asy(const value: TOTPWorkerThreadEvent);
  //
    function  Cancel(taskID: int64): boolean;
    procedure CancelAll;
    function  CountExecuting: integer;
    function  CountQueued: integer;
    function  IsIdle: boolean;
    function  MonitorWith(const monitor: IOmniThreadPoolMonitor): IOmniThreadPool;
    function  RemoveMonitor: IOmniThreadPool;
    function  SetMonitor(hWindow: THandle): IOmniThreadPool;
    property IdleWorkerThreadTimeout_sec: integer read GetIdleWorkerThreadTimeout_sec
      write SetIdleWorkerThreadTimeout_sec;
    property MaxExecuting: integer read GetMaxExecuting write SetMaxExecuting;
    property MaxQueued: integer read GetMaxQueued write SetMaxQueued;
    property MaxQueuedTime_sec: integer read GetMaxQueuedTime_sec write SetMaxQueuedTime_sec;
    property MinWorkers: integer read GetMinWorkers write SetMinWorkers;
    property Name: string read GetName write SetName;
    property UniqueID: int64 read GetUniqueID;
    property WaitOnTerminate_sec: integer read GetWaitOnTerminate_sec write
      SetWaitOnTerminate_sec;
    property OnWorkerThreadCreated_Asy: TOTPWorkerThreadEvent read
      GetOnWorkerThreadCreated_Asy write SetOnWorkerThreadCreated_Asy;
    property OnWorkerThreadDestroying_Asy: TOTPWorkerThreadEvent read
      GetOnWorkerThreadDestroying_Asy write SetOnWorkerThreadDestroying_Asy;
  end; { IOmniThreadPool }

  IOmniThreadPoolScheduler = interface ['{B7F5FFEF-2704-4CE0-ABF1-B20493E73650}']
    procedure Schedule(const task: IOmniTask);
  end; { IOmniThreadPoolScheduler }

  function CreateThreadPool(const threadPoolName: string): IOmniThreadPool;

  function GlobalOmniThreadPool: IOmniThreadPool;

implementation

uses
  Messages,
  Classes,
  Contnrs,
  {$IFNDEF Unicode} //Tiburon provides own TStringBuilder class
  HVStringBuilder,
  {$ENDIF}
  DSiWin32,
  SpinLock,
  GpStuff,
  GpLogger, // TODO 1 -oPrimoz Gabrijelcic : testing, remove!
  OtlCommon,
  OtlComm,
  OtlTaskControl,
  OtlEventMonitor;

const
  WM_REQUEST_COMPLETED = WM_USER;

  MSG_RUN               = 1;
  MSG_THREAD_CREATED    = 2;
  MSG_THREAD_DESTROYING = 3;
  MSG_COMPLETED         = 4;
  MSG_STOP              = 5;
  MSG_WORK_ITEM_DESC    = 6;

type
  {$IFNDEF Unicode}
  TStringBuilder = HVStringBuilder.StringBuilder;
  {$ENDIF}

  TOTPWorkerThread = class;
  TOmniThreadPool = class;

  TOTPWorkItem = class
  strict private
    owiScheduled_ms: int64;
    owiScheduledAt : TDateTime;
    owiStartedAt   : TDateTime;
    owiTask        : IOmniTask;
    owiThread      : TOTPWorkerThread;
  strict protected
    function  GetUniqueID: int64;
  public
    constructor Create(const task: IOmniTask);
    function  Description: string;
    procedure TerminateTask(exitCode: integer; const exitMessage: string);
    property ScheduledAt: TDateTime read owiScheduledAt;
    property Scheduled_ms: int64 read owiScheduled_ms;
    property StartedAt: TDateTime read owiStartedAt write owiStartedAt;
    property UniqueID: int64 read GetUniqueID;
    property Task: IOmniTask read owiTask;
    property Thread: TOTPWorkerThread read owiThread write owiThread;
  end; { TOTPWorkItem }

  TOTPWorkerThread = class(TThread)
  strict private
    owtCommChannel     : IOmniTwoWayChannel;
    owtNewWorkEvent    : TDSiEventHandle;
    owtRemoveFromPool  : boolean;
    owtStartIdle_ms    : int64;
    owtStartStopping_ms: int64;
    owtStopped         : boolean;
    owtTerminateEvent  : TDSiEventHandle;
    owtWorkItem_ref    : TOTPWorkItem;
    owtWorkItemLock    : TTicketSpinLock;
  strict protected
    function  Comm: IOmniCommunicationEndpoint;
    procedure ExecuteWorkItem(workItem: TOTPWorkItem);
    function  GetOwnerCommEndpoint: IOmniCommunicationEndpoint;
    procedure Log(const msg: string; params: array of const);
  public
    constructor Create;
    destructor  Destroy; override;
    function  Asy_Stopped: boolean;
    function  Asy_TerminateWorkItem: boolean;
    function  Description: string;
    procedure Execute; override;
    function  GetWorkItemInfo(var scheduledAt, startedAt: TDateTime;
      var description: string): boolean;
    function  IsExecuting(taskID: int64): boolean;
    procedure Stop;
    function  WorkItemDescription: string;
    property NewWorkEvent: TDSiEventHandle read owtNewWorkEvent;
    property OwnerCommEndpoint: IOmniCommunicationEndpoint read GetOwnerCommEndpoint;
    property RemoveFromPool: boolean read owtRemoveFromPool;
    property StartIdle_ms: int64 read owtStartIdle_ms write owtStartIdle_ms;
    property StartStopping_ms: int64 read owtStartStopping_ms write owtStartStopping_ms; //always modified from the owner thread
    property Stopped: boolean read owtStopped write owtStopped;                          //always modified from the owner thread
    property TerminateEvent: TDSiEventHandle read owtTerminateEvent;
    property WorkItem_ref: TOTPWorkItem read owtWorkItem_ref write owtWorkItem_ref; //address of the work item this thread is working on
  end; { TOTPWorkerThread }

  TOTPWorker = class(TOmniWorker)
  strict private
    owDestroying        : boolean;
    owIdleWorkers       : TObjectList;
    owMonitorSupport    : IOmniMonitorSupport;
    owName              : string;
    owOnThreadCreated   : TOTPWorkerThreadEvent;
    owOnThreadDestroying: TOTPWorkerThreadEvent;
    owRunningWorkers    : TObjectList;
    owStoppingWorkers   : TObjectList;
    owUniqueID          : int64;
    owWorkItemQueue     : TObjectList;
  strict protected
    function  ActiveWorkItemDescriptions: string;
    procedure ForwardThreadCreated(threadID: DWORD);
    procedure ForwardThreadDestroying(threadID: DWORD; threadPoolOperation:
      TThreadPoolOperation);
    procedure InternalStop;
    function LocateThread(threadID: DWORD): TOTPWorkerThread;
    procedure Log(const msg: string; const params: array of const);
    function  NumRunningStoppedThreads: integer;
    procedure ProcessCompletedWorkItem(workItem: TOTPWorkItem);
    procedure RequestCompleted(workItem: TOTPWorkItem; worker: TOTPWorkerThread);
    procedure ScheduleNext(workItem: TOTPWorkItem);
    procedure StopThread(worker: TOTPWorkerThread);
  protected
    procedure Cleanup; override;
    function  Initialize: boolean; override;
  public
    CountQueued                : TGp4AlignedInt;
    CountRunning               : TGp4AlignedInt;
    IdleWorkerThreadTimeout_sec: TGp4AlignedInt;
    MaxExecuting               : TGp4AlignedInt;
    MaxQueued                  : TGp4AlignedInt;
    MaxQueuedTime_sec          : TGp4AlignedInt;
    MinWorkers                 : TGp4AlignedInt;
    WaitOnTerminate_sec        : TGp4AlignedInt;
    constructor Create(const name: string; uniqueID: int64);
  published
    // invoked from TOmniThreadPool
    procedure Cancel(taskID: int64);
    procedure CancelAll;
    procedure GetActiveWorkItemDescriptions;
    procedure MaintainanceTimer;
    procedure PruneWorkingQueue;
    procedure RemoveMonitor;
    procedure Schedule(var workItem: TOTPWorkItem);
    procedure SetMonitor(const hWindow: TOmniValue);
    procedure SetName(const name: TOmniValue);
    procedure SetOnThreadCreated(const eventHandler: TOmniValue);
    procedure SetOnThreadDestroying(const eventHandler: TOmniValue);
    // invoked from TOTPWorkerThreads
    procedure MsgCompleted(var msg: TOmniMessage); message MSG_COMPLETED;
    procedure MsgThreadCreated(var msg: TOmniMessage); message MSG_THREAD_CREATED;
    procedure MsgThreadDestroying(var msg: TOmniMessage); message MSG_THREAD_DESTROYING;
  end; { TOTPWorker }

  TOmniThreadPool = class(TInterfacedObject, IOmniThreadPool, IOmniThreadPoolScheduler)
  strict private
    otpOnThreadCreated   : TOTPWorkerThreadEvent;
    otpOnThreadDestroying: TOTPWorkerThreadEvent;
    otpPoolName          : string;
    otpUniqueID          : int64;
    otpWorker            : IOmniWorker;
    otpWorkerTask        : IOmniTaskControl;
  strict protected
    function  GetActiveWorkItemDescriptions: string;
    procedure Log(const msg: string; const params: array of const);
  protected
    function  GetIdleWorkerThreadTimeout_sec: integer;
    function  GetMaxExecuting: integer;
    function  GetMaxQueued: integer;
    function  GetMaxQueuedTime_sec: integer;
    function  GetMinWorkers: integer;
    function  GetName: string;
    function  GetOnWorkerThreadCreated_Asy: TOTPWorkerThreadEvent;
    function  GetOnWorkerThreadDestroying_Asy: TOTPWorkerThreadEvent;
    function  GetUniqueID: int64;
    function  GetWaitOnTerminate_sec: integer;
    procedure SetIdleWorkerThreadTimeout_sec(value: integer);
    procedure SetMaxExecuting(value: integer);
    procedure SetMaxQueued(value: integer);
    procedure SetMaxQueuedTime_sec(value: integer);
    procedure SetMinWorkers(value: integer);
    procedure SetName(const value: string);
    procedure SetOnWorkerThreadCreated_Asy(const value: TOTPWorkerThreadEvent);
    procedure SetOnWorkerThreadDestroying_Asy(const value: TOTPWorkerThreadEvent);
    procedure SetWaitOnTerminate_sec(value: integer);
    function WorkerObj: TOTPWorker;
  public
    constructor Create(const name: string);
    destructor  Destroy; override;
    function  Cancel(taskID: int64): boolean;
    procedure CancelAll;
    function  CountExecuting: integer;
    function  CountQueued: integer;
    function  IsIdle: boolean;
    function  MonitorWith(const monitor: IOmniThreadPoolMonitor): IOmniThreadPool;
    function  RemoveMonitor: IOmniThreadPool;
    procedure Schedule(const task: IOmniTask);
    function  SetMonitor(hWindow: THandle): IOmniThreadPool;
    property IdleWorkerThreadTimeout_sec: integer read GetIdleWorkerThreadTimeout_sec
      write SetIdleWorkerThreadTimeout_sec;
    property MaxExecuting: integer read GetMaxExecuting write SetMaxExecuting;
    property MaxQueued: integer read GetMaxQueued write SetMaxQueued;
    property MaxQueuedTime_sec: integer read GetMaxQueuedTime_sec write SetMaxQueuedTime_sec;
    property MinWorkers: integer read GetMinWorkers write SetMinWorkers;
    property Name: string read GetName write SetName;
    property UniqueID: int64 read GetUniqueID;
    property WaitOnTerminate_sec: integer read GetWaitOnTerminate_sec write
      SetWaitOnTerminate_sec;
    property OnWorkerThreadCreated_Asy: TOTPWorkerThreadEvent
      read GetOnWorkerThreadCreated_Asy write SetOnWorkerThreadCreated_Asy;
    property OnWorkerThreadDestroying_Asy: TOTPWorkerThreadEvent
      read GetOnWorkerThreadDestroying_Asy write SetOnWorkerThreadDestroying_Asy;
  end; { TOmniThreadPool }

const
  CGlobalOmniThreadPoolName = 'GlobalOmniThreadPool';

var
  GOmniThreadPool: IOmniThreadPool = nil;

{ exports }

function GlobalOmniThreadPool: IOmniThreadPool;
begin
  if not assigned(GOmniThreadPool) then
    GOmniThreadPool := CreateThreadPool(CGlobalOmniThreadPoolName);
  Result := GOmniThreadPool;
end; { GlobalOmniThreadPool }

function CreateThreadPool(const threadPoolName: string): IOmniThreadPool;
begin
  Result := TOmniThreadPool.Create(threadPoolName);
end; { CreateThreadPool }

{ TOmniThreadPoolMonitorInfo }

constructor TOmniThreadPoolMonitorInfo.Create(uniqueID: int64; threadPoolOperation:
  TThreadPoolOperation; threadID: integer);
begin
  otpmiUniqueID := uniqueID;
  otpmiThreadPoolOperation := threadPoolOperation;
  otpmiThreadID := threadID;
end; { TOmniThreadPoolMonitorInfo.Create }

constructor TOmniThreadPoolMonitorInfo.Create(uniqueID, taskID: int64);
begin
  otpmiUniqueID := uniqueID;
  otpmiThreadPoolOperation := tpoWorkItemCompleted;
  otpmiTaskID := taskID;
end; { TOmniThreadPoolMonitorInfo.Create }

{ TOTPWorkItem }

constructor TOTPWorkItem.Create(const task: IOmniTask);
begin
  inherited Create;
  owiTask := task;
  owiScheduledAt := Now;
  owiScheduled_ms := DSiTimeGetTime64;
end; { TOTPWorkItem.Create }

function TOTPWorkItem.Description: string;
begin
  Result := Format('%s:%d', [Task.Name, UniqueID]);
end; { TOTPWorkItem.Description }

function TOTPWorkItem.GetUniqueID: int64;
begin
  if assigned(Task) then
    Result := Task.UniqueID
  else
    Result := -1;
end; { TOTPWorkItem.GetUniqueID }

procedure TOTPWorkItem.TerminateTask(exitCode: integer; const exitMessage: string);
begin
  if assigned(owiTask) then begin
    owiTask.SetExitStatus(exitCode, exitMessage);
    owiTask.Terminate;
    owiTask := nil;
  end;
end; { TOTPWorkItem.TerminateTask }

{ TOTPWorkerThread }

constructor TOTPWorkerThread.Create;
begin
  inherited Create(true);
  {$IFDEF LogThreadPool}Log('Creating thread %s', [Description]);{$ENDIF LogThreadPool}
  owtNewWorkEvent := CreateEvent(nil, false, false, nil);
  owtTerminateEvent := CreateEvent(nil, false, false, nil);
  owtWorkItemLock := TTicketSpinLock.Create; // TODO 1 -oPrimoz Gabrijelcic : Do we need it anymore?
  owtCommChannel := CreateTwoWayChannel;
  Resume;
end; { TOTPWorkerThread.Create }

destructor TOTPWorkerThread.Destroy;
begin
  {$IFDEF LogThreadPool}Log('Destroying thread %s', [Description]);{$ENDIF LogThreadPool}
//GpLog.Log('Destroying thread %d and comm channel %d', [ThreadID, OwnerCommEndpoint.NewMessageEvent]);
  FreeAndNil(owtWorkItemLock);
  DSiCloseHandleAndNull(owtTerminateEvent);
  DSiCloseHandleAndNull(owtNewWorkEvent);
  inherited Destroy;
end; { TOTPWorkerThread.Destroy }

function TOTPWorkerThread.Asy_Stopped: boolean;
var
  task: IOmniTask;
begin
  Result := true;
  owtWorkItemLock.Acquire;
  try
    if assigned(WorkItem_ref) then begin
      task := WorkItem_ref.Task;
      if assigned(task) then
        Result := task.Stopped;
    end;
  finally owtWorkItemLock.Release end;
end; { TOTPWorkerThread.Asy_Stopped }

///<summary>Take the work item ownership from the thread. Called asynchronously from the thread pool.</summary>
///<returns>True if thread should be killed.</returns>
///<since>2008-07-26</since>
function TOTPWorkerThread.Asy_TerminateWorkItem: boolean;
var
  workItem: TOTPWorkItem;
begin
  {$IFDEF LogThreadPool}Log('Asy_TerminateWorkItem thread %s', [Description]);{$ENDIF LogThreadPool}
  Result := false;
  owtWorkItemLock.Acquire;
  try
    if assigned(WorkItem_ref) then begin
      {$IFDEF LogThreadPool}Log('Thread %s has work item', [Description]);{$ENDIF LogThreadPool}
      workItem := WorkItem_ref;
      WorkItem_ref := nil;
      if assigned(workItem) and assigned(workItem.Task) and (not workItem.Task.Stopped) then begin
        workItem.TerminateTask(EXIT_THREADPOOL_CANCELLED, 'Cancelled');
//        Owner.Asy_RequestCompleted(workItem, Self);
        Result := true;
      end
      else if assigned(workItem) then begin
//        Owner.Asy_RequestCompleted(workItem, Self);
        Result := false;
      end;
    end;
  finally owtWorkItemLock.Release end;
end; { TOTPWorkerThread.Asy_TerminateWorkItem }

function TOTPWorkerThread.Comm: IOmniCommunicationEndpoint;
begin
  Result := owtCommChannel.Endpoint1;
end; { TOTPWorkerThread.Comm }

function TOTPWorkerThread.Description: string;
begin
  if not assigned(Self) then
    Result := '<none>'
  else
    Result := Format('%p:%d', [pointer(Self), GetCurrentThreadID]);
end; { TOTPWorkerThread.Description }

procedure TOTPWorkerThread.Execute;
var
  msg: TOmniMessage;
begin
  {$IFDEF LogThreadPool}Log('>>>Execute thread %s', [Description]);{$ENDIF LogThreadPool}
  Comm.Send(MSG_THREAD_CREATED, ThreadID);
  try
    while true do begin
      if Comm.ReceiveWait(msg, INFINITE) then begin
        case msg.MsgID of
          MSG_RUN:
            ExecuteWorkItem(TOTPWorkItem(msg.MsgData.AsObject));
          MSG_STOP:
            begin
              Stop;
              break; //while
            end;
          else
            raise Exception.CreateFmt('TOTPWorkerThread.Execute: Unexpected message %d',
                    [msg.MsgID]);
        end; //case
      end; //if Comm.ReceiveWait
    end; //while Comm.ReceiveWait()
  finally Comm.Send(MSG_THREAD_DESTROYING, ThreadID); end;
  {$IFDEF LogThreadPool}Log('<<<Execute thread %s', [Description]);{$ENDIF LogThreadPool}
end; { TOTPWorkerThread.Execute }

procedure TOTPWorkerThread.ExecuteWorkItem(workItem: TOTPWorkItem);
var
  creationTime   : TDateTime;
  startKernelTime: int64;
  startUserTime  : int64;
  stopKernelTime : int64;
  stopUserTime   : int64;
  task           : IOmniTask;
begin
  WorkItem_ref := workItem; // TODO 1 -oPrimoz Gabrijelcic : still needed?
  task := WorkItem_ref.Task;
  try
    try
      {$IFDEF LogThreadPool}Log('Thread %s starting execution of %s', [Description, WorkItem_ref.Description]);{$ENDIF LogThreadPool}
      DSiGetThreadTimes(creationTime, startUserTime, startKernelTime);
      if assigned(task) then
        (task as IOmniTaskExecutor).Execute;
      DSiGetThreadTimes(creationTime, stopUserTime, stopKernelTime);
      {$IFDEF LogThreadPool}Log('Thread %s completed execution of %s; user time = %d ms, kernel time = %d ms', [Description, WorkItem_ref.Description, Round((stopUserTime - startUserTime)/10000), Round((stopKernelTime - startKernelTime)/10000)]);{$ENDIF LogThreadPool}
    except
      on E: Exception do begin
        {$IFDEF LogThreadPool}Log('Thread %s caught exception %s during exection of %s', [Description, E.Message, WorkItem_ref.Description]);{$ENDIF LogThreadPool}
        if assigned(task) then
          task.SetExitStatus(EXIT_EXCEPTION, E.Message);
        //owtRemoveFromPool := true;
        // TODO 1 -oPrimoz Gabrijelcic : That should happen automatically when task exits with EXIT_EXCEPTION 
      end;
    end;
  finally task := nil; end;
  owtWorkItemLock.Acquire;
  try
    workItem := WorkItem_ref;
    WorkItem_ref := nil;
    if assigned(workItem) then begin // not already canceled
      {$IFDEF LogThreadPool}Log('Thread %s sending notification of completed work item %s', [Description, workItem.Description]);{$ENDIF LogThreadPool}
      Comm.Send(MSG_COMPLETED, workItem);
    end;
  finally owtWorkItemLock.Release; end;
end; { TOTPWorkerThread.ExecuteWorkItem }

function TOTPWorkerThread.GetOwnerCommEndpoint: IOmniCommunicationEndpoint;
begin
  Result := owtCommChannel.Endpoint2;
end; { TOTPWorkerThread.GetOwnerCommEndpoint }

function TOTPWorkerThread.GetWorkItemInfo(var scheduledAt, startedAt: TDateTime; var
  description: string): boolean;
begin
  owtWorkItemLock.Acquire;
  try
    if not assigned(WorkItem_ref) then
      Result := false
    else begin
      scheduledAt := WorkItem_ref.ScheduledAt;
      startedAt := WorkItem_ref.StartedAt;
      description := WorkItem_ref.Description; UniqueString(description);
      Result := true;
    end;
  finally owtWorkItemLock.Release; end;
end; { TOTPWorkerThread.GetWorkItemInfo }

function TOTPWorkerThread.IsExecuting(taskID: int64): boolean;
begin
  owtWorkItemLock.Acquire;
  try
    Result := assigned(WorkItem_ref) and (WorkItem_ref.UniqueID = taskID);
  finally owtWorkItemLock.Release; end;
end; { TOTPWorkerThread.IsExecuting }

procedure TOTPWorkerThread.Log(const msg: string; params: array of const);
begin
  {$IFDEF LogThreadPool}
  Owner.Log(msg, params);
  {$ENDIF LogThreadPool}
end; { TOTPWorkerThread.Log }

///<summary>Gently stop the worker thread.
procedure TOTPWorkerThread.Stop;
var
  task: IOmniTask;
begin
  {$IFDEF LogThreadPool}Log('Stop thread %s', [Description]);{$ENDIF LogThreadPool}
  owtWorkItemLock.Acquire; // TODO 1 -oPrimoz Gabrijelcic : probably don't need it anymore
  try
    if assigned(WorkItem_ref) then begin
      task := WorkItem_ref.Task;
      if assigned(task) then
        task.Terminate;
    end;
  finally owtWorkItemLock.Release end;
end; { TOTPWorkerThread.Stop }

function TOTPWorkerThread.WorkItemDescription: string;
begin
  owtWorkItemLock.Acquire;
  try
    if assigned(WorkItem_ref) then begin
      Result := WorkItem_ref.Description;
    end
    else
      Result := '';
  finally owtWorkItemLock.Release; end;
end; { TOTPWorkerThread.WorkItemDescription }

{ TOTPWorker }

constructor TOTPWorker.Create(const name: string; uniqueID: int64);
begin
  inherited Create;
  owName := name;
  owUniqueID := uniqueID;
end; { TOTPWorker.Create }

function TOTPWorker.ActiveWorkItemDescriptions: string;
var
  description   : string;
  iWorker       : integer;
  sbDescriptions: TStringBuilder;
  scheduledAt   : TDateTime;
  startedAt     : TDateTime;
  worker        : TOTPWorkerThread;
begin
  sbDescriptions := TStringBuilder.Create;
  try
    for iWorker := 0 to owRunningWorkers.Count - 1 do begin
      worker := TOTPWorkerThread(owRunningWorkers[iWorker]);
      if worker.GetWorkItemInfo(scheduledAt, startedAt, description) then
        sbDescriptions.
          Append('[').Append(iWorker+1).Append('] ').
          Append(FormatDateTime('hh:nn:ss', scheduledAt)).Append(' / ').
          Append(FormatDateTime('hh:nn:ss', startedAt)).Append(' ').
          Append(description);
    end;
    Result := sbDescriptions.ToString;
  finally FreeAndNil(sbDescriptions); end;
end; { TGpThreadPool.ActiveWorkItemDescriptions }

///<returns>True: Normal exit, False: Thread was killed.</returns>
procedure TOTPWorker.Cancel(taskID: int64);
var
  endWait_ms: int64;
  iWorker   : integer;
  worker    : TOTPWorkerThread;
begin
  // TODO 1 -oPrimoz Gabrijelcic : Reimplement
  (*
  Result := true;
  for iWorker := 0 to otpRunningWorkers.Count - 1 do begin
    worker := TOTPWorkerThread(otpRunningWorkers[iWorker]);
    if worker.IsExecuting(taskID) then begin
      {$IFDEF LogThreadPool}Log('Cancel request %d on thread %p:%d', [taskID, pointer(worker), worker.ThreadID]);{$ENDIF LogThreadPool}
      otpRunningWorkers.Delete(iWorker);
      worker.Asy_Stop(false);
      endWait_ms := DSiTimeGetTime64 + int64(WaitOnTerminate_sec)*1000;
      while (DSiTimeGetTime64 < endWait_ms) and (not worker.Asy_Stopped) do
        Sleep(100);
      if worker.Asy_TerminateWorkItem then begin
        {$IFDEF LogThreadPool}Log('Terminating unstoppable thread %s, num idle = %d, num running = %d[%d]', [worker.Description, tpIdleWorkers.Count, tpRunningWorkers.Count, MaxExecuting]);{$ENDIF LogThreadPool}
        otpRunningWorkers.Remove(worker);
        otpMonitorSupport.Notify(
          TOmniThreadPoolMonitorInfo.Create(UniqueID, tpoKillThread, worker.ThreadID));
        TerminateThread(worker.Handle, cardinal(-1));
        FreeAndNil(worker);
        Result := false;
      end
      else begin
        otpIdleWorkers.Add(worker);
        {$IFDEF LogThreadPool}Log('Thread %s moved to the idle list, num idle = %d, num running = %d[%d]', [worker.Description, tpIdleWorkers.Count, tpRunningWorkers.Count, MaxExecuting]);{$ENDIF LogThreadPool}
      end;
      break; //for
    end;
  end; //for iWorker
  *)
end; { TOTPWorker.Cancel }

procedure TOTPWorker.CancelAll;
begin
  // TODO 1 -oPrimoz Gabrijelcic : implement: TOTPWorker.CancelAll
  //InternalStop
end; { TOTPWorker.CancelAll }

procedure TOTPWorker.Cleanup;
begin
  owDestroying := true;
  FreeAndNil(owStoppingWorkers);
  FreeAndNil(owRunningWorkers);
  FreeAndNil(owIdleWorkers);
  FreeAndNil(owWorkItemQueue);
end; { TOTPWorker.Cleanup }

procedure TOTPWorker.ForwardThreadCreated(threadID: DWORD);
begin
  if assigned(owOnThreadCreated) then
    owOnThreadCreated(Self, threadID);
  owMonitorSupport.Notify(
    TOmniThreadPoolMonitorInfo.Create(owUniqueID, tpoCreateThread, threadID));
end; { TOTPWorker.ForwardThreadCreated }

procedure TOTPWorker.ForwardThreadDestroying(threadID: DWORD; threadPoolOperation:
  TThreadPoolOperation);
var
  worker: TOTPWorkerThread;
begin
  worker := LocateThread(threadID);
  if assigned(worker) then begin
//GpLog.Log('Unregistering Comm endpoint %d for worker thread %d', [worker.OwnerCommEndpoint.NewMessageEvent, threadID]);
    Task.UnregisterComm(worker.OwnerCommEndpoint);
    Worker.Stopped := true;
  end
  else begin
//GpLog.Log('Cannot find thread %d - cannot unregister Comm endpoint', [threadID]);
  end;
  if assigned(owOnThreadDestroying) then
    owOnThreadDestroying(Self, threadID);
  owMonitorSupport.Notify(
    TOmniThreadPoolMonitorInfo.Create(owUniqueID, threadPoolOperation, threadID));
end; { TOTPWorker.ForwardThreadDestroying }

procedure TOTPWorker.GetActiveWorkItemDescriptions;
begin
  Task.Comm.Send(MSG_WORK_ITEM_DESC, ActiveWorkItemDescriptions);
end; { TGpThreadPool.GetActiveWorkItemDescriptions }

function TOTPWorker.Initialize: boolean;
begin
  owMonitorSupport := CreateOmniMonitorSupport;
  owIdleWorkers := TObjectList.Create(false);
  owRunningWorkers := TObjectList.Create(false);
  CountRunning.Value := 0;
  owStoppingWorkers := TObjectList.Create(false);
  owWorkItemQueue := TObjectList.Create(false);
  CountQueued.Value := 0;
  IdleWorkerThreadTimeout_sec.Value := CDefaultIdleWorkerThreadTimeout_sec;
  WaitOnTerminate_sec.Value := CDefaultWaitOnTerminate_sec;
  MaxExecuting.Value := Length(DSiGetThreadAffinity);
  Task.SetTimer(1000, @TOTPWorker.MaintainanceTimer);
  Result := true;
end; { TOTPWorker.Initialize }

procedure TOTPWorker.InternalStop;
var
  endWait_ms : int64;
  iWorker    : integer;
  iWorkItem  : integer;
  queuedItems: TObjectList {of TOTPWorkItem};
  worker     : TOTPWorkerThread;
  workItem   : TOTPWorkItem;
begin
  {$IFDEF LogThreadPool}Log('Terminating queued tasks', []);{$ENDIF LogThreadPool}
  queuedItems := TObjectList.Create(false);
  try
    for iWorkItem := 0 to owWorkItemQueue.Count - 1 do
      queuedItems.Add(owWorkItemQueue[iWorkItem]);
    owWorkItemQueue.Clear;
    CountQueued.Value := 0;
    for iWorkItem := 0 to queuedItems.Count - 1 do begin
      workItem := TOTPWorkItem(queuedItems[iWorkItem]);
      workItem.TerminateTask(EXIT_THREADPOOL_CANCELLED, 'Cancelled');
      RequestCompleted(workItem, nil);
    end; //for iWorkItem
  finally FreeAndNil(queuedItems); end;
  {$IFDEF LogThreadPool}Log('Stopping all threads', []);{$ENDIF LogThreadPool}
  // TODO 1 -oPrimoz Gabrijelcic : Reimplement
//  for iWorker := 0 to owIdleWorkers.Count - 1 do
//    StopThread(TOTPWorkerThread(owIdleWorkers[iWorker]));
  owIdleWorkers.Clear;
//  for iWorker := 0 to owRunningWorkers.Count - 1 do
//    StopThread(TOTPWorkerThread(owRunningWorkers[iWorker]));
  owRunningWorkers.Clear;
  CountRunning.Value := 0;
  endWait_ms := DSiTimeGetTime64 + int64(WaitOnTerminate_sec)*1000;
  while (endWait_ms > DSiTimeGetTime64) and (NumRunningStoppedThreads > 0) do
    Sleep(100);
  for iWorker := 0 to owStoppingWorkers.Count - 1 do begin
    worker := TOTPWorkerThread(owStoppingWorkers[iWorker]);
    worker.Asy_TerminateWorkItem;
    FreeAndNil(worker);
  end;
  owStoppingWorkers.Clear;
end; { TGpThreadPool.InternalStop }

function TOTPWorker.LocateThread(threadID: DWORD): TOTPWorkerThread;
var
  oThread: pointer;
begin
  for oThread in owRunningWorkers do begin
    Result := TOTPWorkerThread(oThread);
    if Result.ThreadID = threadID then
      Exit;
  end;
  for oThread in owIdleWorkers do begin
    Result := TOTPWorkerThread(oThread);
    if Result.ThreadID = threadID then
      Exit;
  end;
  for oThread in owStoppingWorkers do begin
    Result := TOTPWorkerThread(oThread);
    if Result.ThreadID = threadID then
      Exit;
  end;
  Result := nil;
end; { TOTPWorker.LocateThread }

procedure TOTPWorker.Log(const msg: string; const params: array of const);
begin
  // TODO 1 -oPrimoz Gabrijelcic : Pass log messages to the event monitor
  {$IFDEF LogThreadPool}
  // use whatever logger you want
  {$ENDIF LogThreadPool}
end; { TOTPWorker.Log }

procedure TOTPWorker.MaintainanceTimer;
var
  iWorker: integer;
  worker : TOTPWorkerThread;
begin
  PruneWorkingQueue;
  if IdleWorkerThreadTimeout_sec > 0 then begin
    iWorker := 0;
    while (owIdleWorkers.CardCount > MinWorkers.Value) and (iWorker < owIdleWorkers.Count) do begin
      worker := TOTPWorkerThread(owIdleWorkers[iWorker]);
      if (worker.StartStopping_ms = 0) and
         ((worker.StartIdle_ms + int64(IdleWorkerThreadTimeout_sec)*1000) < DSiTimeGetTime64) then
      begin
        {$IFDEF LogThreadPool}Log('Destroying idle thread %s because it was idle for more than %d seconds', [worker.Description, IdleWorkerThreadTimeout_sec]);{$ENDIF LogThreadPool}
        owIdleWorkers.Delete(iWorker);
        StopThread(worker);
      end
      else
        Inc(iWorker);
    end; //while
  end;
  iWorker := 0;
  while iWorker < owStoppingWorkers.Count do begin
    worker := TOTPWorkerThread(owStoppingWorkers[iWorker]);
    if worker.Stopped or
       ((worker.StartStopping_ms + int64(WaitOnTerminate_sec)*1000) < DSiTimeGetTime64) then
    begin
      if not worker.Stopped then begin
        SuspendThread(worker.Handle);
        if worker.Stopped then begin
          ResumeThread(worker.Handle);
          break; //while
        end;
        TerminateThread(worker.Handle, 0); 
        ForwardThreadDestroying(worker.ThreadID, tpoKillThread);
      end
      else begin
        {$IFDEF LogThreadPool}Log('Removing stopped thread %s', [worker.Description]);{$ENDIF LogThreadPool}
      end;
      owStoppingWorkers.Delete(iWorker);
//GpLog.Log('Destroying worker %d', [worker.ThreadID]);
      FreeAndNil(worker);
    end
    else
      Inc(iWorker);
  end;
end; { TOTPWorker.MaintainanceTimer }

procedure TOTPWorker.MsgCompleted(var msg: TOmniMessage);
begin
  ProcessCompletedWorkItem(TOTPWorkItem(msg.MsgData.AsObject));
end; { TOTPWorker.MsgCompleted }

procedure TOTPWorker.MsgThreadCreated(var msg: TOmniMessage);
begin
  ForwardThreadCreated(msg.MsgData);
end; { TOTPWorker.MsgThreadCreated }

procedure TOTPWorker.MsgThreadDestroying(var msg: TOmniMessage);
begin
//GpLog.Log('Recevied MSG_THREAD_DESTROYING[%d]', [integer(msg.MsgData)]);
  ForwardThreadDestroying(msg.MsgData, tpoDestroyThread);
end; { TOTPWorker.MsgThreadDestroying }

///<summary>Counts number of threads in the 'stopping' queue that are still doing work.</summary>
///<since>2007-07-10</since>
function TOTPWorker.NumRunningStoppedThreads: integer;
var
  iThread: integer;
  worker : TOTPWorkerThread;
begin
  Result := 0;
  for iThread := 0 to owStoppingWorkers.Count - 1 do begin
    worker := TOTPWorkerThread(owStoppingWorkers[iThread]);
    if assigned(worker.WorkItem_ref) then
      Inc(Result);
  end; //for iThread
end; { TOTPWorker.NumRunningStoppedThreads }

procedure TOTPWorker.ProcessCompletedWorkItem(workItem: TOTPWorkItem);
var
  worker: TOTPWorkerThread;
begin
  worker := workItem.Thread;
  {$IFDEF LogThreadPool}Log('Thread %s completed request %s with status %s:%s',
    [worker.Description, workItem.Description, GetEnumName(TypeInfo(TGpTPStatus), Ord(workItem.Status)), workItem.LastError]);{$ENDIF LogThreadPool}
  if owDestroying then begin
    FreeAndNil(workItem);
    Exit;
  end;
  owMonitorSupport.Notify(
    TOmniThreadPoolMonitorInfo.Create(owUniqueID, workItem.UniqueID));
  {$IFDEF LogThreadPool}Log('Thread %s completed request %s with status %s:%s', [worker.Description, workItem.Description, GetEnumName(TypeInfo(TGpTPStatus), Ord(workItem.Status)), workItem.LastError]);{$ENDIF LogThreadPool}
  {$IFDEF LogThreadPool}Log('Destroying %s', [workItem.Description]);{$ENDIF LogThreadPool}
  FreeAndNil(workItem);
  if owStoppingWorkers.IndexOf(worker) >= 0 then
    owStoppingWorkers.Remove(worker);
  if owRunningWorkers.IndexOf(worker) < 0 then
    worker := nil;
  if assigned(worker) then begin // move it back to the idle queue
    owRunningWorkers.Extract(worker);
    CountRunning.Decrement;
    if (not worker.RemoveFromPool) and (owRunningWorkers.CardCount < MaxExecuting.Value) then begin
      worker.StartIdle_ms := DSiTimeGetTime64;
      owIdleWorkers.Add(worker);
      {$IFDEF LogThreadPool}Log('Thread %s moved back to the idle list, num idle = %d, num running = %d[%d]', [worker.Description, tpIdleWorkers.Count, tpRunningWorkers.Count, MaxExecuting]);{$ENDIF LogThreadPool}
    end
    else begin
      {$IFDEF LogThreadPool}Log('Destroying thread %s, num idle = %d, num running = %d[%d]', [worker.Description, tpIdleWorkers.Count, tpRunningWorkers.Count, MaxExecuting]);{$ENDIF LogThreadPool}
      StopThread(worker);
    end;
  end;
  // TODO 1 -oPrimoz Gabrijelcic : check!
  if (not owDestroying) and (owWorkItemQueue.Count > 0) and
     ((owIdleWorkers.Count > 0) or (owRunningWorkers.CardCount < MaxExecuting.Value)) then
  begin
    workItem := TOTPWorkItem(owWorkItemQueue[0]);
    owWorkItemQueue.Delete(0);
    CountQueued.Decrement;
    {$IFDEF LogThreadPool}Log('Dequeueing %s ', [workItem.Description]);{$ENDIF LogThreadPool}
    ScheduleNext(workItem);
  end;
end; { TOTPWorker.ProcessCompletedWorkItem }

procedure TOTPWorker.PruneWorkingQueue;
var
  errorMsg      : string;
  iWorkItem     : integer;
  maxWaitTime_ms: int64;
  workItem      : TOTPWorkItem;
begin
  if MaxQueued.Value > 0 then begin
    while owWorkItemQueue.CardCount > MaxQueued.Value do begin
      workItem := TOTPWorkItem(owWorkItemQueue[owWorkItemQueue.Count - 1]);
      {$IFDEF LogThreadPool}Log('Removing request %s from work item queue because queue length > %d', [workItem.Description, tpMaxQueueLength]);{$ENDIF LogThreadPool}
      owWorkItemQueue.Delete(owWorkItemQueue.Count - 1);
      CountQueued.Decrement;
      errorMsg := Format('Execution queue is too long (%d work items)', [owWorkItemQueue.Count]);
      workItem.TerminateTask(EXIT_THREADPOOL_QUEUE_TOO_LONG, errorMsg);
      RequestCompleted(workItem, nil); 
    end; //while
  end;
  if MaxQueuedTime_sec.Value > 0 then begin
    iWorkItem := 0;
    while iWorkItem < owWorkItemQueue.Count do begin
      workItem := TOTPWorkItem(owWorkItemQueue[iWorkItem]);
      maxWaitTime_ms := workItem.Scheduled_ms + int64(MaxQueuedTime_sec.Value)*1000;
      if maxWaitTime_ms > DSiTimeGetTime64 then
        Inc(iWorkItem)
      else begin
        {$IFDEF LogThreadPool}Log('Removing request %s from work item queue because it is older than %d seconds', [workItem.Description, tpMaxQueuedTime_sec]);{$ENDIF LogThreadPool}
        owWorkItemQueue.Delete(iWorkItem);
        CountQueued.Decrement;
        errorMsg := Format('Maximum queued time exceeded.' +
          ' Pool = %0:s, Now = %1:s, Max executing = %2:d,' +
          ' Removed entry queue time = %3:s, Removed entry description = %4:s.' +
          ' Active entries: %5:s',
          [{0}owName, {1}FormatDateTime('hh:nn:ss', Now), {2}MaxExecuting.Value,
           {3}FormatDateTime('hh:nn:ss', workItem.ScheduledAt),
           {4}workItem.Description, {5}ActiveWorkItemDescriptions]);
        workItem.TerminateTask(EXIT_THREADPOOL_STALE_TASK, errorMsg);
        RequestCompleted(workItem, nil);
      end;
    end; //while
  end;
end; { TOTPWorker.PruneWorkingQueue }

procedure TOTPWorker.RemoveMonitor;
begin
  owMonitorSupport.RemoveMonitor;
end; { TOTPWorker.RemoveMonitor }

procedure TOTPWorker.RequestCompleted(workItem: TOTPWorkItem; worker: TOTPWorkerThread);
begin
  workItem.Thread := worker;
  ProcessCompletedWorkItem(workItem);
end; { TOTPWorker.RequestCompleted }

procedure TOTPWorker.Schedule(var workItem: TOTPWorkItem);
begin
  ScheduleNext(workItem);
  PruneWorkingQueue;
end; { TOTPWorker.Schedule }

procedure TOTPWorker.ScheduleNext(workItem: TOTPWorkItem);
var
  worker: TOTPWorkerThread;
begin
  worker := nil;
  if owIdleWorkers.Count > 0 then begin
    worker := TOTPWorkerThread(owIdleWorkers[owIdleWorkers.Count - 1]);
    owIdleWorkers.Delete(owIdleWorkers.Count - 1);
    owRunningWorkers.Add(worker);
    CountRunning.Increment;
    {$IFDEF LogThreadPool}Log('Allocated thread from idle pool, num idle = %d, num running = %d[%d]', [owIdleWorkers.Count, owRunningWorkers.Count, MaxExecuting]);{$ENDIF LogThreadPool}
  end
  else if (MaxExecuting.Value <= 0) or (owRunningWorkers.CardCount < MaxExecuting.Value) then begin
    worker := TOTPWorkerThread.Create;
//GpLog.Log('Registering Comm endpoint %d for worker thread %d', [worker.OwnerCommEndpoint.NewMessageEvent, worker.ThreadID]);
    Task.RegisterComm(worker.OwnerCommEndpoint);
    // TODO 1 -oPrimoz Gabrijelcic : Unregister endpoint before the thread is destroyed
    owRunningWorkers.Add(worker);
    CountRunning.Increment;
    {$IFDEF LogThreadPool}Log('Created new thread %s, num idle = %d, num running = %d[%d]', [worker.Description, owIdleWorkers.Count, owRunningWorkers.Count, MaxExecuting]);{$ENDIF LogThreadPool}
  end;
  if assigned(worker) then begin
    {$IFDEF LogThreadPool}Log('Started %s', [workItem.Description]);{$ENDIF LogThreadPool}
    workItem.StartedAt := Now;
    workItem.Thread := worker;
    //worker.WorkItem_ref := workItem;
    worker.OwnerCommEndpoint.Send(MSG_RUN, workItem);
  end
  else begin
    {$IFDEF LogThreadPool}Log('Queued %s ', [workItem.Description]);{$ENDIF LogThreadPool}
    owWorkItemQueue.Add(workItem);
    CountQueued.Increment;
    if (MaxQueued > 0) and (owWorkItemQueue.CardCount >= MaxQueued.Value) then
      PruneWorkingQueue;
  end;
end; { TOTPWorker.ScheduleNext }

procedure TOTPWorker.SetMonitor(const hWindow: TOmniValue);
begin
  owMonitorSupport.SetMonitor(CreateOmniMonitorParams(hWindow, COmniPoolMsg, 0, 0));
end; { TOTPWorker.SetMonitor }

procedure TOTPWorker.SetName(const name: TOmniValue);
begin
  owName := name;
end; { TOTPWorker.SetName }

procedure TOTPWorker.SetOnThreadCreated(const eventHandler: TOmniValue);
begin
  TMethod(owOnThreadCreated).Code := pointer(cardinal(eventHandler[0]));
  TMethod(owOnThreadCreated).Data := pointer(cardinal(eventHandler[1]));
end; { TOTPWorker.SetOnThreadCreated }

procedure TOTPWorker.SetOnThreadDestroying(const eventHandler: TOmniValue);
begin
  TMethod(owOnThreadDestroying).Code := pointer(cardinal(eventHandler[0]));
  TMethod(owOnThreadDestroying).Data := pointer(cardinal(eventHandler[1]));
end; { TOTPWorker.SetOnThreadDestroying }

///<summary>Move the thread to the 'stopping' list and tell it to CancelAll.<para>
///   Thread is guaranted not to be in 'idle' or 'working' list when StopThread is called.</para></summary>
///<since>2007-07-10</since>
procedure TOTPWorker.StopThread(worker: TOTPWorkerThread);
begin
  {$IFDEF LogThreadPool}Log('Stopping worker thread %s', [worker.Description]);{$ENDIF LogThreadPool}
  owStoppingWorkers.Add(worker);
  worker.StartStopping_ms := DSiTimeGetTime64;
  worker.OwnerCommEndpoint.Send(MSG_STOP);
  {$IFDEF LogThreadPool}Log('num stopped = %d', [tpStoppingWorkers.Count]);{$ENDIF LogThreadPool}
end; { TOTPWorker.StopThread }

{ TOmniThreadPool }

constructor TOmniThreadPool.Create(const name: string);
begin
  inherited Create;
  {$IFDEF LogThreadPool}Log('Creating thread pool %p [%s]', [pointer(self), name]);{$ENDIF LogThreadPool}
  otpPoolName := name;
  otpUniqueID := OtlUID.Increment;
  otpWorker := TOTPWorker.Create(name, otpUniqueID);
  otpWorkerTask := CreateTask(otpWorker, Format('OmniThreadPool manager %s', [name])).Run;
end; { TOmniThreadPool.Create }

destructor TOmniThreadPool.Destroy;
begin
  {$IFDEF LogThreadPool}Log('Destroying thread pool %p', [pointer(self), otpPoolName]);{$ENDIF LogThreadPool}
  otpWorkerTask.Terminate;
  inherited;
end; { TOmniThreadPool.Destroy }

///<returns>True: Normal exit, False: Thread was killed.</returns>
function TOmniThreadPool.Cancel(taskID: int64): boolean;
begin
  otpWorkerTask.Invoke(@TOTPWorker.Cancel, taskID);
end; { TOmniThreadPool.Cancel }

procedure TOmniThreadPool.CancelAll;
begin
  otpWorkerTask.Invoke(@TOTPWorker.CancelAll);
end; { TOmniThreadPool.CancelAll }

function TOmniThreadPool.CountExecuting: integer;
begin
  Result := WorkerObj.CountRunning.Value;
end; { TOmniThreadPool.CountExecuting }

function TOmniThreadPool.CountQueued: integer;
begin
  Result := WorkerObj.CountQueued.Value;
end; { TOmniThreadPool.CountQueued }

function TOmniThreadPool.GetActiveWorkItemDescriptions: string;
var
  msg: TOmniMessage;
begin
  otpWorkerTask.Invoke(@TOTPWorker.GetActiveWorkItemDescriptions);
  otpWorkerTask.Comm.ReceiveWait(msg, INFINITE);
  Assert(msg.MsgID = MSG_WORK_ITEM_DESC);
  Result := msg.MsgData;
end; { TGpThreadPool.GetActiveWorkItemDescriptions }

function TOmniThreadPool.GetIdleWorkerThreadTimeout_sec: integer;
begin
  Result := WorkerObj.IdleWorkerThreadTimeout_sec.Value;
end; { TOmniThreadPool.GetIdleWorkerThreadTimeout_sec }

function TOmniThreadPool.GetMaxExecuting: integer;
begin
  Result := WorkerObj.MaxExecuting.Value;
end; { TOmniThreadPool.GetMaxExecuting }

function TOmniThreadPool.GetMaxQueued: integer;
begin
  Result := WorkerObj.MaxQueued.Value;
end; { TOmniThreadPool.GetMaxQueued }

function TOmniThreadPool.GetMaxQueuedTime_sec: integer;
begin
  Result := WorkerObj.MaxQueuedTime_sec.Value;
end; { TOmniThreadPool.GetMaxQueuedTime_sec }

function TOmniThreadPool.GetMinWorkers: integer;
begin
  Result := WorkerObj.MinWorkers.Value;
end; { TOmniThreadPool.GetMinWorkers }

function TOmniThreadPool.GetName: string;
begin
  Result := otpPoolName;
end; { TOmniThreadPool.GetName }

function TOmniThreadPool.GetOnWorkerThreadCreated_Asy: TOTPWorkerThreadEvent;
begin
  Result := otpOnThreadCreated;
end; { TOmniThreadPool.GetOnWorkerThreadCreated_Asy }

function TOmniThreadPool.GetOnWorkerThreadDestroying_Asy: TOTPWorkerThreadEvent;
begin
  Result := otpOnThreadDestroying;
end; { TOmniThreadPool.GetOnWorkerThreadDestroying_Asy }

function TOmniThreadPool.GetUniqueID: int64;
begin
  Result := otpUniqueID;
end; { TOmniThreadPool.GetUniqueID }

function TOmniThreadPool.GetWaitOnTerminate_sec: integer;
begin
  Result := WorkerObj.WaitOnTerminate_sec.Value;
end; { TOmniThreadPool.GetWaitOnTerminate_sec }

function TOmniThreadPool.IsIdle: boolean;
begin
  if CountQueued <> 0 then
    Result := false
  else if CountExecuting <> 0 then
    Result := false
  else
    Result := true;
end; { TOmniThreadPool.IsIdle }

procedure TOmniThreadPool.Log(const msg: string; const params: array of const);
begin
  {$IFDEF LogThreadPool}
  // use whatever logger you want
  {$ENDIF LogThreadPool}
end; { TGpThreadPool.Log }

function TOmniThreadPool.MonitorWith(const monitor: IOmniThreadPoolMonitor): IOmniThreadPool;
begin
  monitor.Monitor(Self); // TODO 1 -oPrimoz Gabrijelcic : That good or should we be monitoring TOTPWorker???
  Result := Self;
end; { TOmniThreadPool.MonitorWith }

function TOmniThreadPool.RemoveMonitor: IOmniThreadPool;
begin
  otpWorkerTask.Invoke(@TOTPWorker.RemoveMonitor);
  Result := Self;
end; { TOmniThreadPool.RemoveMonitor }

procedure TOmniThreadPool.Schedule(const task: IOmniTask);
begin
  otpWorkerTask.Invoke(@TOTPWorker.Schedule, TOTPWorkItem.Create(task));
end; { TOmniThreadPool.Schedule }

procedure TOmniThreadPool.SetIdleWorkerThreadTimeout_sec(value: integer);
begin
  WorkerObj.IdleWorkerThreadTimeout_sec.Value := value;
end; { TOmniThreadPool.SetIdleWorkerThreadTimeout_sec }

procedure TOmniThreadPool.SetMaxExecuting(value: integer);
begin
  WorkerObj.MaxExecuting.Value := value;
end; { TOmniThreadPool.SetMaxExecuting }

procedure TOmniThreadPool.SetMaxQueued(value: integer);
begin
  WorkerObj.MaxQueued.Value := value;
  otpWorkerTask.Invoke(@TOTPWorker.PruneWorkingQueue);
end; { TOmniThreadPool.SetMaxQueued }

procedure TOmniThreadPool.SetMaxQueuedTime_sec(value: integer);
begin
  WorkerObj.MaxQueuedTime_sec.Value := value;
  otpWorkerTask.Invoke(@TOTPWorker.PruneWorkingQueue);
end; { TOmniThreadPool.SetMaxQueuedTime_sec }

procedure TOmniThreadPool.SetMinWorkers(value: integer);
begin
  WorkerObj.MinWorkers.Value := value;
end; { TOmniThreadPool.SetMinWorkers }

function TOmniThreadPool.SetMonitor(hWindow: THandle): IOmniThreadPool;
begin
  otpWorkerTask.Invoke(@TOTPWorker.SetMonitor, hWindow);
  Result := Self;
end; { TOmniThreadPool.SetMonitor }

procedure TOmniThreadPool.SetName(const value: string);
begin
  otpPoolName := value;
  otpWorkerTask.Invoke(@TOTPWorker.SetName, value);
end; { TOmniThreadPool.SetName }

procedure TOmniThreadPool.SetOnWorkerThreadCreated_Asy(const value:
  TOTPWorkerThreadEvent);
begin
  otpOnThreadCreated := value;
  otpWorkerTask.Invoke(@TOTPWorker.SetOnThreadCreated,
    [TMethod(value).Code, TMethod(value).Data]);
end; { TOmniThreadPool.SetOnWorkerThreadCreated_Asy }

procedure TOmniThreadPool.SetOnWorkerThreadDestroying_Asy(const value:
  TOTPWorkerThreadEvent);
begin
  otpOnThreadDestroying := value;
  otpWorkerTask.Invoke(@TOTPWorker.SetOnThreadDestroying,
    [TMethod(value).Code, TMethod(value).Data]);
end; { TOmniThreadPool.SetOnWorkerThreadDestroying_Asy }

procedure TOmniThreadPool.SetWaitOnTerminate_sec(value: integer);
begin
  WorkerObj.WaitOnTerminate_sec.Value := value;
end; { TOmniThreadPool.SetWaitOnTerminate_sec }

function TOmniThreadPool.WorkerObj: TOTPWorker;
begin
  Result := (otpWorker.Implementor as TOTPWorker);
end; { TOmniThreadPool.WorkerObj }

initialization
  //assumptions made in the code above
  Assert(SizeOf(pointer) = SizeOf(cardinal));
end.

