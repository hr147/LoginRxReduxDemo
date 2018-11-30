//
//  FeedbackViewModel.swift
//  LoginDemoRxRedux
//
//  Created by Mounir Dellagi on 26.06.18.
//  Copyright © 2018 Mounir Dellagi. All rights reserved.
//

import Foundation
import RxFeedback
import RxSwift
import RxCocoa

struct LoginStore {
    fileprivate let inputEvents: Signal<Event>

    init(inputs: LoginView.Outputs, alertInput: Signal<RxAlertResult>) {
        self.inputEvents = Signal.merge(
            inputs.usernameField.map { .usernameChanged($0) },
            inputs.passwordField.map { .passwordChanged($0) },
            inputs.loginButton.map { .loginButtonTapped },
            inputs.showPasswordButton.map { .passwordToggled },
            alertInput.map { _ in .errorMessageDismissed }
        )
    }
    lazy var output: Driver<LoginView.Model> = {
        let initalStateModel = StateModel(credentials: Credentials(username: "", password: ""), isPasswordHidden: true, state: .loggedOut)
        let context = Context()

        return StateModel.outputStates(initialState: initalStateModel,
                                  inputEvents: inputEvents,
                                  context: context)
            .map { stateModel in LoginView.Model(stateModel: stateModel) }
            .distinctUntilChanged()
    }()

    fileprivate struct Context { // Will be done by David or/and Stefan in Interactor/Use Case Refactor
    }

    /// The actions that can be performed on the view model
    fileprivate enum Event: Equatable {
        case usernameChanged(String)
        case passwordChanged(String)
        case loginButtonTapped
        case passwordToggled
        case errorMessageDismissed

        case loginRequestSucceeded(User) // Asynchronous Feedback Event
        case loginRequestFailed(APIError) // Asynchronous Feedback Event
    }

    fileprivate enum Effect: TriggerableEffect {
        case loginRequest(loginPayload: LoginRequestModel)

        fileprivate func trigger(context: Context) -> Signal<Event> {
            switch self {
            case .loginRequest(let requestModel):
                let api: LoginAPIProtocol = DependencyRetriever.loginApi()
                let requestModel = LoginRequestModel(username: requestModel.username, password: requestModel.password)
                return api.loginUser(loginPayload: requestModel)
                    .map { response -> Event in .loginRequestSucceeded(response) }
                    .asSignal { error in
                        return Signal.just(Event.loginRequestFailed((error as? APIError)!))
                    }
                    .delay(1)
            }
        }
    }

    fileprivate struct Credentials: Hashable {
        let username: String
        let password: String
    }

    enum State: Hashable {
        case loggedOut, loggedIn(User), loginFailed(APIError), performingLogin
    }

    fileprivate struct StateModel: ReducibleStateWithEffects {
        let credentials: Credentials
        let isPasswordHidden: Bool
        let state: State

        fileprivate func reduce(event: Event) -> (state: StateModel, effects: Set<Effect>) {
            switch (state, event) {
            case (.loggedOut, .passwordToggled):
                return (StateModel(credentials: credentials, isPasswordHidden: !isPasswordHidden, state: .loggedOut), [])

            case (.loggedOut, .usernameChanged(let username)):
                let newCredentials = Credentials(username: username, password: credentials.password)
                return (StateModel(credentials: newCredentials, isPasswordHidden: isPasswordHidden, state: .loggedOut), [])

            case (.loggedOut, .passwordChanged(let password)):
                let newCredentials = Credentials(username: credentials.username, password: password)
                return (StateModel(credentials: newCredentials, isPasswordHidden: isPasswordHidden, state: .loggedOut), [])

            case (.loggedOut, .loginButtonTapped):
                return (StateModel(credentials: credentials, isPasswordHidden: isPasswordHidden, state: .performingLogin),
                        [.loginRequest(loginPayload: LoginRequestModel(username: credentials.username, password: credentials.password))])

            case (.performingLogin, .loginRequestSucceeded(let user)):
                return (StateModel(credentials: credentials, isPasswordHidden: isPasswordHidden, state: .loggedIn(user)), [])

            case (.performingLogin, .loginRequestFailed(let error)):
                return (StateModel(credentials: credentials, isPasswordHidden: isPasswordHidden, state: .loginFailed(error)), [])

            case (.loginFailed, .errorMessageDismissed):
                return (StateModel(credentials: credentials, isPasswordHidden: isPasswordHidden, state: .loggedOut), [])
            default:
                return (self, [])

            }
        }
    }
}

private extension LoginStore.Credentials {
    private func checkPasswordValidity(_ password: String) -> Bool {
        return password.count > 7 && password.rangeOfCharacter(from: CharacterSet.alphanumerics) != nil
    }

    var valid: Bool {
        return username.count > 5 && checkPasswordValidity(password)
    }
}

private extension LoginView.Model {
    init(stateModel: LoginStore.StateModel) {
        self.isSpinning = stateModel.state == .performingLogin
        self.isLoginButtonEnabled = stateModel.credentials.valid && stateModel.state != .performingLogin
        self.isPasswordHidden = stateModel.isPasswordHidden
        self.state = stateModel.state
    }
}
